defmodule PokerServerWeb.GameLive.Show do
  use PokerServerWeb, :live_view

  alias PokerServer.{GameManager, UIAdapter}
  alias Phoenix.PubSub

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}")
    end

    # Just verify game exists, actual state loaded in handle_params
    case GameManager.get_game_state(game_id) do
      {:ok, _game_server_state} ->
        socket =
          socket
          |> assign(:game_id, game_id)
          |> assign(:current_player, nil)  # Will be set in handle_params
          |> assign(:player_view, nil)     # Will be set in handle_params

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
  def handle_event("start_hand", _params, socket) do
    case GameManager.lookup_game(socket.assigns.game_id) do
      {:ok, pid} ->
        case PokerServer.GameServer.start_hand(pid) do
          {:ok, _new_state} ->
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start hand: #{reason}")}
        end

      {:error, :game_not_found} ->
        {:noreply, put_flash(socket, :error, "Game not found")}
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
  def handle_event("back_to_lobby", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:game_updated, _game_server_state}, socket) do
    # Get fresh UI state when game updates
    case UIAdapter.get_player_view(socket.assigns.game_id, socket.assigns.current_player) do
      {:ok, player_view} ->
        {:noreply, assign(socket, :player_view, player_view)}
      {:error, _reason} ->
        {:noreply, socket}
    end
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
      <.header>
        Poker Game
        <:subtitle>
          Game ID: <%= @game_id %> | Player: <%= @current_player %>
        </:subtitle>
        <:actions>
          <.button phx-click="back_to_lobby" class="bg-gray-600 hover:bg-gray-700">
            Back to Lobby
          </.button>
        </:actions>
      </.header>

      <!-- Game Display using UIAdapter -->
      <div :if={@player_view} class="mt-8 bg-white rounded-lg shadow-md p-6">
        <h2 class="text-xl font-semibold mb-4">Game Status</h2>
        
        <!-- Game info from UIAdapter -->
        <div class="grid grid-cols-2 gap-4 mb-6">
          <div>
            <span class="text-gray-600">Phase:</span>
            <span class="font-medium capitalize"><%= @player_view.phase || "waiting" %></span>
          </div>
          <div>
            <span class="text-gray-600">Hand Number:</span>
            <span class="font-medium"><%= @player_view.hand_number || 0 %></span>
          </div>
          <div>
            <span class="text-gray-600">Pot:</span>
            <span class="font-medium">$<%= @player_view.pot %></span>
          </div>
          <div>
            <span class="text-gray-600">Your Chips:</span>
            <span class="font-medium">$<%= @player_view.current_player.chips %></span>
          </div>
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
          <div :if={@player_view.can_start_hand}>
            <p class="mb-4">Game is ready. You can start a hand.</p>
            <.button phx-click="start_hand" class="bg-green-600 hover:bg-green-700">
              Start Hand
            </.button>
          </div>

          <div :if={@player_view.can_act}>
            <p class="mb-4">Your turn to act</p>
            <div class="flex justify-center gap-3 flex-wrap">
              <.button 
                :if={:fold in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="fold" 
                class="bg-red-600 hover:bg-red-700">
                Fold
              </.button>
              <.button 
                :if={:call in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="call" 
                class="bg-blue-600 hover:bg-blue-700">
                Call $<%= @player_view.betting_info.call_amount %>
              </.button>
              <.button 
                :if={:check in @player_view.valid_actions}
                phx-click="player_action" 
                phx-value-action="check" 
                class="bg-gray-600 hover:bg-gray-700">
                Check
              </.button>
            </div>
          </div>

          <div :if={not @player_view.can_act and not @player_view.can_start_hand and not @player_view.is_waiting_for_players}>
            <p class="text-gray-600">Waiting for other players...</p>
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