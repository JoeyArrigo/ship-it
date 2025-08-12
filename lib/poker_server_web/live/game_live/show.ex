defmodule PokerServerWeb.GameLive.Show do
  use PokerServerWeb, :live_view

  alias PokerServer.{GameManager, UIAdapter}
  alias Phoenix.PubSub

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    # Note: PubSub subscription moved to apply_action when current_player is known

    # Just verify game exists, actual state loaded in handle_params
    case GameManager.get_game_state(game_id) do
      {:ok, _game_server_state} ->
        socket =
          socket
          |> assign(:game_id, game_id)
          # Will be set in handle_params
          |> assign(:current_player, nil)
          # Will be set in handle_params
          |> assign(:player_view, nil)

        {:ok, socket}

      {:error, :game_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, params) do
    current_player = Map.get(params, "player")

    if is_nil(current_player) do
      socket
      |> put_flash(:error, "Please join through the lobby")
      |> push_navigate(to: ~p"/")
    else
      # Subscribe to player-specific channel for filtered updates
      if connected?(socket) do
        PubSub.subscribe(PokerServer.PubSub, "game:#{socket.assigns.game_id}:#{current_player}")
      end

      # Get player view and validate player is in game
      case UIAdapter.get_player_view(socket.assigns.game_id, current_player) do
        {:ok, player_view} ->
          socket
          |> assign(:page_title, "Poker Game")
          |> assign(:current_player, current_player)
          |> assign(:player_view, player_view)

        {:error, reason} ->
          # Log the error for debugging
          IO.inspect(reason, label: "UIAdapter error")

          socket
          |> put_flash(:error, "Error loading game: #{inspect(reason)}")
          |> push_navigate(to: ~p"/")
      end
    end
  end

  @impl true
  def handle_event("player_action", %{"action" => "fold"}, socket) do
    make_player_action(socket, {:fold})
  end

  @impl true
  def handle_event("player_action", %{"action" => "call"}, socket) do
    make_player_action(socket, {:call})
  end

  @impl true
  def handle_event("player_action", %{"action" => "check"}, socket) do
    make_player_action(socket, {:check})
  end

  @impl true
  def handle_event("player_action", %{"action" => "raise", "amount" => amount_str}, socket) do
    case Integer.parse(amount_str) do
      {amount, ""} when amount > 0 ->
        make_player_action(socket, {:raise, amount})

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid raise amount")}
    end
  end

  @impl true
  def handle_event("player_action", %{"action" => "all_in"}, socket) do
    make_player_action(socket, {:all_in})
  end

  @impl true
  def handle_event("start_hand", _params, socket) do
    case GameManager.lookup_game(socket.assigns.game_id) do
      {:ok, pid} ->
        case PokerServer.GameServer.start_hand(pid) do
          {:ok, _state} ->
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start hand: #{inspect(reason)}")}
        end

      {:error, :game_not_found} ->
        {:noreply, put_flash(socket, :error, "Game not found")}
    end
  end

  @impl true
  def handle_event("back_to_lobby", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:game_updated, filtered_player_view}, socket) do
    # Receive pre-filtered player view from GameServer (no need to re-filter)
    {:noreply, assign(socket, :player_view, filtered_player_view)}
  end

  # Helper function to make player actions via the service
  defp make_player_action(socket, action) do
    current_player = socket.assigns.current_player

    if is_nil(current_player) do
      {:noreply, put_flash(socket, :error, "Player not identified")}
    else
      case GameManager.player_action(socket.assigns.game_id, current_player, action) do
        {:ok, _result, _state} ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Action failed: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <!-- Game Display using UIAdapter -->
      <div :if={@player_view} class="mt-2 bg-white rounded-lg shadow-md p-4 md:p-6">
        
        <!-- 2-Player Opponent Display -->
        <%= if length(@player_view.players) == 2 do %>
          <% opponent = Enum.find(@player_view.players, &(not &1.is_current_player)) %>
          <div :if={opponent} class="mb-6 p-4 rounded-lg border-2 border-gray-200 bg-gray-50">
            <div class="flex justify-between items-center">
              <div class="flex items-center gap-3">
                <span class="text-lg font-semibold text-gray-900"><%= opponent.id %></span>
                <span class="text-sm px-2 py-1 rounded-full bg-blue-100 text-blue-800">
                  <%= if @player_view.can_act do %>
                    Waiting
                  <% else %>
                    <%= if not @player_view.can_start_hand and not @player_view.is_waiting_for_players do %>
                      Thinking...
                    <% else %>
                      <%= if @player_view.can_start_hand, do: "Ready", else: "Waiting" %>
                    <% end %>
                  <% end %>
                </span>
              </div>
              <div class="text-lg font-bold text-green-600">
                $<%= opponent.chips %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Prominent Pot Display -->
        <div class="text-center mb-6">
          <div class="text-3xl font-bold text-green-600 mb-1">$<%= @player_view.pot %></div>
          <div class="text-sm text-gray-600">Pot</div>
        </div>
        
        <!-- Simplified Game info -->
        <div class="flex justify-between items-center mb-6 text-sm text-gray-600">
          <div>Hand #<%= @player_view.hand_number || 0 %></div>
          <div>Your Chips: <span class="font-semibold text-gray-900">$<%= @player_view.current_player.chips %></span></div>
        </div>

        <!-- Community Cards -->
        <div :if={length(@player_view.community_cards) > 0} class="mb-6">
          <h3 class="text-lg font-medium mb-2">Community Cards</h3>
          <div class="flex gap-2">
            <span 
              :for={card <- @player_view.community_cards} 
              class={"px-2 py-1 rounded border text-#{card.color} bg-white"}>
              <%= card.display %>
            </span>
          </div>
        </div>

        <!-- Your Cards -->
        <div :if={length(@player_view.current_player.hole_cards) > 0} class="mb-6">
          <h3 class="text-lg font-medium mb-2">Your Cards</h3>
          <div class="flex gap-2">
            <span 
              :for={card <- @player_view.current_player.hole_cards} 
              class={"px-2 py-1 rounded border text-#{card.color} bg-white"}>
              <%= card.display %>
            </span>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="text-center">

          <div :if={@player_view.can_act}>
            <p class="mb-4">Your turn to act</p>
            
            <!-- Mobile-optimized action buttons -->
            <div class="grid grid-cols-2 gap-3 mb-4">
              <.button 
                :if={:fold in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="fold" 
                class="bg-red-600 hover:bg-red-700 text-lg py-3">
                Fold
              </.button>
              <.button 
                :if={:call in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="call" 
                class="bg-blue-600 hover:bg-blue-700 text-lg py-3">
                Call $<%= @player_view.betting_info.call_amount %>
              </.button>
              <.button 
                :if={:check in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="check" 
                class="bg-gray-600 hover:bg-gray-700 text-lg py-3 col-span-2">
                Check
              </.button>
              <.button 
                :if={:all_in in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="all_in" 
                class="bg-purple-600 hover:bg-purple-700 text-lg py-3 col-span-2">
                All-In ($<%= @player_view.current_player.chips %>)
              </.button>
            </div>

            <!-- Mobile-optimized raise controls -->
            <div :if={:raise in @player_view.valid_actions} class="bg-gray-50 rounded-lg p-3">
              <form phx-submit="player_action" class="space-y-3">
                <div class="flex items-center gap-3">
                  <input 
                    name="amount"
                    type="number" 
                    placeholder="Amount" 
                    min={@player_view.betting_info.min_raise}
                    max={@player_view.current_player.chips + (@player_view.betting_info.call_amount || 0)}
                    class="flex-1 text-center border border-gray-300 rounded-lg px-3 py-2 text-lg"
                    required
                  />
                  <.button type="submit" class="bg-orange-600 hover:bg-orange-700 text-lg py-2 px-6">
                    Raise
                  </.button>
                </div>
                <div class="text-sm text-gray-600 text-center">
                  Min: $<%= @player_view.betting_info.min_raise %>
                </div>
                <input type="hidden" name="action" value="raise" />
              </form>
            </div>
          </div>

          <!-- Showdown Results -->
          <div :if={@player_view.showdown_results} class="mb-6">
            <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <h3 class="text-lg font-semibold mb-3 text-center">Showdown Results</h3>
              
              <!-- Winner Announcement -->
              <%= for winner_id <- @player_view.showdown_results.winners do %>
                <div class="text-center mb-4">
                  <div class="text-xl font-bold text-green-600">
                    <%= if winner_id == @current_player, do: "You Win!", else: "#{winner_id} Wins!" %>
                  </div>
                  <div class="text-sm text-gray-600">
                    <%= @player_view.showdown_results.hand_descriptions[winner_id] %>
                  </div>
                </div>
              <% end %>
              
              <!-- All Player Hands -->
              <div class="space-y-3">
                <%= for player <- @player_view.players do %>
                  <%= if length(player.hole_cards) > 0 do %>
                    <div class={"flex justify-between items-center p-3 rounded-lg " <>
                      if player.id in @player_view.showdown_results.winners do
                        "bg-green-100 border border-green-300"
                      else
                        "bg-gray-100"
                      end}>
                      <div class="flex items-center gap-3">
                        <span class="font-medium">
                          <%= if player.is_current_player, do: "You", else: player.id %>
                        </span>
                        <div class="flex gap-1">
                          <%= for card <- player.hole_cards do %>
                            <span class={"px-2 py-1 rounded border text-#{card.color} bg-white text-sm"}>
                              <%= card.display %>
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <div class="text-sm text-gray-600">
                        <%= @player_view.showdown_results.hand_descriptions[player.id] %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <div :if={@player_view.can_start_hand}>
            <p class="mb-4">Hand complete! Ready to start next hand?</p>
            <.button 
              phx-click="start_hand" 
              class="bg-green-600 hover:bg-green-700">
              Start New Hand
            </.button>
          </div>

          <div :if={not @player_view.can_act and not @player_view.can_start_hand and not @player_view.is_waiting_for_players}>
            <% opponent = if length(@player_view.players) == 2, do: Enum.find(@player_view.players, &(not &1.is_current_player)) %>
            <p class="text-gray-600">
              <%= if opponent do %>
                Waiting for <%= opponent.id %>...
              <% else %>
                Waiting for other players...
              <% end %>
            </p>
          </div>
        </div>
      </div>

      <!-- Debug Info (temporary) -->
      <div :if={@player_view} class="mt-4 bg-gray-100 rounded-lg p-4">
        <details>
          <summary class="cursor-pointer font-medium">Debug: Player View</summary>
          <pre class="mt-2 text-xs overflow-auto"><%= inspect(@player_view, pretty: true) %></pre>
        </details>
      </div>
    </div>
    """
  end
end
