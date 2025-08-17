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
  def handle_event("play_again", _params, socket) do
    current_player = socket.assigns.current_player
    
    if current_player && socket.assigns.player_view do
      # Get all players from the current game
      players = socket.assigns.player_view.players
      
      # Create player list with 1500 starting chips each (tournament format)
      player_list = Enum.map(players, fn player -> {player.id, 1500} end)
      
      case PokerServer.GameManager.create_game(player_list) do
        {:ok, new_game_id} ->
          # Auto-start the first hand
          case PokerServer.GameManager.lookup_game(new_game_id) do
            {:ok, game_pid} ->
              PokerServer.GameServer.start_hand(game_pid)
              
              # Broadcast new game URL to all players in the current game
              Enum.each(players, fn player ->
                PubSub.broadcast(PokerServer.PubSub, "game:#{socket.assigns.game_id}:#{player.id}", 
                  {:redirect_to_new_game, new_game_id})
              end)
              
              # Redirect current player to the new game
              {:noreply, 
               socket
               |> put_flash(:info, "New game started!")
               |> push_navigate(to: ~p"/game/#{new_game_id}?player=#{current_player}")}
            
            {:error, :game_not_found} ->
              {:noreply, put_flash(socket, :error, "Failed to start new game")}
          end
        
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create new game: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unable to restart game")}
    end
  end

  @impl true
  def handle_info({:game_updated, filtered_player_view}, socket) do
    # Receive pre-filtered player view from GameServer (no need to re-filter)
    {:noreply, assign(socket, :player_view, filtered_player_view)}
  end

  @impl true
  def handle_info({:redirect_to_new_game, new_game_id}, socket) do
    # Redirect to the new game when another player starts it
    current_player = socket.assigns.current_player
    {:noreply, 
     socket
     |> put_flash(:info, "New game started!")
     |> push_navigate(to: ~p"/game/#{new_game_id}?player=#{current_player}")}
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

  # Check if debug info should be shown based on environment variable
  defp show_debug?() do
    System.get_env("SHOW_DEBUG_PLAYER_VIEW", "false") == "true"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto relative px-2 sm:px-4">
      <!-- Neo Wave Game Interface -->
      <div :if={@player_view} class="mt-2 neo-table relative overflow-hidden">
        <!-- Floating particle effects -->
        <div class="neo-particles">
          <div class="neo-particle" style="left: 10%; animation-delay: 0s;"></div>
          <div class="neo-particle" style="left: 20%; animation-delay: 2s;"></div>
          <div class="neo-particle" style="left: 30%; animation-delay: 4s;"></div>
          <div class="neo-particle" style="left: 70%; animation-delay: 6s;"></div>
          <div class="neo-particle" style="left: 80%; animation-delay: 8s;"></div>
          <div class="neo-particle" style="left: 90%; animation-delay: 1s;"></div>
        </div>
        
        <!-- Neo Wave Opponent Display -->
        <%= if length(@player_view.players) == 2 do %>
          <% opponent = Enum.find(@player_view.players, &(not &1.is_current_player)) %>
          <div :if={opponent} class="mb-4 sm:mb-8 neo-player-pos relative">
            <!-- Mobile: Stack layout, Desktop: Horizontal layout -->
            <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center">
              <!-- Player info section -->
              <div class="flex flex-col sm:flex-row items-center gap-2 sm:gap-4">
                <!-- Avatar centered on mobile -->
                <div class="w-12 h-12 sm:w-12 sm:h-12 rounded-full neo-avatar flex items-center justify-center text-white font-bold">
                  <%= String.first(opponent.id) |> String.upcase() %>
                </div>
                <!-- Text content below avatar on mobile, beside on desktop -->
                <div class="text-center sm:text-left">
                  <span class="text-lg sm:text-xl font-bold text-gray-900 block"><%= opponent.id %></span>
                  <div class={["neo-status inline-block mt-1 sm:mt-0", cond do
                    @player_view.can_act -> "waiting"
                    not @player_view.can_start_hand and not @player_view.is_waiting_for_players -> "thinking"
                    true -> "active"
                  end]}>
                    <%= if @player_view.can_act do %>
                      Waiting
                    <% else %>
                      <%= if not @player_view.can_start_hand and not @player_view.is_waiting_for_players do %>
                        Thinking...
                      <% else %>
                        <%= if @player_view.can_start_hand, do: "Ready", else: "Waiting" %>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
              <!-- Chips - centered on mobile, right on desktop -->
              <div class="neo-chips text-lg sm:text-xl mt-2 sm:mt-0 self-center sm:self-auto">
                <span class="text-xl sm:text-2xl neo-bitcoin">₿</span> <%= opponent.chips %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Neo Wave Pot Display -->
        <div class="neo-pot">
          <div class="neo-pot-amount"><span class="neo-bitcoin">₿</span><%= @player_view.pot %></div>
          <div class="neo-pot-label">Total Pot</div>
          <!-- Pot odds information for betting decisions -->
          <div :if={@player_view.can_act and :call in @player_view.valid_actions} class="mt-2 text-xs text-gray-600">
            <% call_amount = @player_view.betting_info.call_amount %>
            <% pot_odds = if call_amount > 0, do: trunc(@player_view.pot / call_amount * 100), else: 0 %>
            <span class="font-medium">Pot Odds: <%= pot_odds %>% • Call to Win <%= @player_view.pot + call_amount %></span>
          </div>
        </div>
        
        <!-- Neo Wave Game Info -->
        <div class="flex justify-between items-center mb-4 sm:mb-8 glass-neo p-3 sm:p-4">
          <div class="text-gray-900 font-semibold text-sm sm:text-base">
            <span class="text-cyan-600 font-bold">HAND</span> #<%= @player_view.hand_number || 0 %>
          </div>
          <div class="neo-chips text-sm sm:text-base">
            <span class="text-base sm:text-lg neo-bitcoin">₿</span> <%= @player_view.current_player.chips %>
          </div>
        </div>

        <!-- Neo Wave Community Cards -->
        <div :if={length(@player_view.community_cards) > 0} class="neo-community mb-4 sm:mb-8">
          <h3 class="text-lg sm:text-xl font-bold mb-3 sm:mb-4 gradient-text">COMMUNITY BOARD</h3>
          <div class="flex gap-2 sm:gap-3 justify-center flex-wrap">
            <div 
              :for={card <- @player_view.community_cards} 
              class={"neo-card " <> 
                case card.color do
                  "red-600" -> "pink-suit"
                  "blue-600" -> "cyan-suit" 
                  "green-600" -> "green-suit"
                  "gray-900" -> "yellow-suit"
                  _ -> "yellow-suit"
                end}>
              <%= card.display %>
            </div>
          </div>
        </div>

        <!-- Neo Wave Player Cards -->
        <div :if={length(@player_view.current_player.hole_cards) > 0} class="mb-4 sm:mb-8">
          <div class="glass-neo p-4 sm:p-6 text-center">
            <h3 class="text-lg sm:text-xl font-bold mb-3 sm:mb-4">
              <span class="gradient-text">YOUR HAND</span>
            </h3>
            <div class="flex gap-3 sm:gap-4 justify-center">
              <div 
                :for={card <- @player_view.current_player.hole_cards} 
                class={"neo-card transform hover:scale-110 transition-transform " <> 
                  case card.color do
                    "red-600" -> "pink-suit"
                    "blue-600" -> "cyan-suit" 
                    "green-600" -> "green-suit"
                    "gray-900" -> "yellow-suit"
                    _ -> "yellow-suit"
                  end}>
                <%= card.display %>
              </div>
            </div>
          </div>
        </div>

        <!-- Neo Wave Action Interface -->
        <div class="text-center">

          <div :if={@player_view.can_act}>
            <div class="glass-neo p-4 sm:p-6 mb-4 sm:mb-6">
              <p class="mb-4 sm:mb-6 text-lg sm:text-xl font-bold">
                <span class="gradient-text">YOUR TURN</span>
              </p>
              
              <!-- Neo Wave action buttons -->
              <div class="grid grid-cols-2 gap-3 sm:gap-4 mb-4 sm:mb-6">
                <button 
                  :if={:fold in @player_view.valid_actions}
                  phx-click="player_action" 
                  phx-value-action="fold" 
                  class="neo-btn neo-btn-danger text-sm sm:text-lg py-3 sm:py-4 px-4 sm:px-6">
                  <span>FOLD</span>
                </button>
                <button 
                  :if={:call in @player_view.valid_actions}
                  phx-click="player_action" 
                  phx-value-action="call" 
                  class="neo-btn neo-btn-primary text-sm sm:text-lg py-3 sm:py-4 px-4 sm:px-6">
                  <span>CALL <span class="neo-bitcoin">₿</span><%= @player_view.betting_info.call_amount %></span>
                </button>
                <button 
                  :if={:check in @player_view.valid_actions}
                  phx-click="player_action" 
                  phx-value-action="check" 
                  class="neo-btn neo-btn-secondary text-sm sm:text-lg py-3 sm:py-4 px-4 sm:px-6 col-span-2">
                  <span>CHECK</span>
                </button>
                <button 
                  :if={:all_in in @player_view.valid_actions}
                  phx-click="player_action" 
                  phx-value-action="all_in" 
                  class="neo-btn neo-btn-primary text-sm sm:text-lg py-3 sm:py-4 px-4 sm:px-6 col-span-2 relative overflow-hidden">
                  <span>ALL-IN (<span class="neo-bitcoin">₿</span><%= @player_view.current_player.chips %>)</span>
                  <div class="absolute inset-0 bg-gradient-to-r from-pink-500 to-yellow-500 opacity-0 hover:opacity-20 transition-opacity"></div>
                </button>
              </div>

              <!-- Neo Wave raise controls -->
              <div :if={:raise in @player_view.valid_actions} class="glass-neo p-3 sm:p-4 mt-3 sm:mt-4">
                <div class="space-y-4">
                  <!-- Quick bet amount buttons -->
                  <div class="mb-4">
                    <p class="text-xs sm:text-sm text-gray-600 text-center font-medium mb-3 uppercase tracking-wider">Quick Bets</p>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                      <button 
                        phx-click="player_action" 
                        phx-value-action="raise" 
                        phx-value-amount={div(@player_view.pot, 2)}
                        class="neo-btn neo-btn-secondary text-xs sm:text-sm py-2 px-3 relative group">
                        <span>½ POT</span>
                        <div class="text-xs opacity-75">₿<%= div(@player_view.pot, 2) %></div>
                      </button>
                      <button 
                        phx-click="player_action" 
                        phx-value-action="raise" 
                        phx-value-amount={div(@player_view.pot * 3, 4)}
                        class="neo-btn neo-btn-secondary text-xs sm:text-sm py-2 px-3 relative group">
                        <span>¾ POT</span>
                        <div class="text-xs opacity-75">₿<%= div(@player_view.pot * 3, 4) %></div>
                      </button>
                      <button 
                        phx-click="player_action" 
                        phx-value-action="raise" 
                        phx-value-amount={@player_view.pot}
                        class="neo-btn neo-btn-primary text-xs sm:text-sm py-2 px-3 relative group">
                        <span>POT</span>
                        <div class="text-xs opacity-75">₿<%= @player_view.pot %></div>
                      </button>
                      <button 
                        phx-click="player_action" 
                        phx-value-action="raise" 
                        phx-value-amount={@player_view.pot * 2}
                        class="neo-btn neo-btn-primary text-xs sm:text-sm py-2 px-3 relative group">
                        <span>2× POT</span>
                        <div class="text-xs opacity-75">₿<%= @player_view.pot * 2 %></div>
                      </button>
                    </div>
                  </div>

                  <!-- Custom raise form -->
                  <form phx-submit="player_action" class="space-y-3">
                    <div class="flex flex-col sm:flex-row items-center gap-3 sm:gap-4">
                      <input 
                        id="raise-amount"
                        name="amount"
                        type="number" 
                        placeholder="Custom Amount" 
                        min={@player_view.betting_info.min_raise}
                        max={@player_view.current_player.chips + (@player_view.betting_info.call_amount || 0)}
                        class="w-full sm:flex-1 text-center bg-white/95 backdrop-blur border-2 border-cyan-400/50 rounded-2xl px-3 sm:px-4 py-2 sm:py-3 text-base sm:text-lg font-bold text-gray-900 placeholder-gray-400 focus:border-pink-500 focus:outline-none transition-colors"
                        required
                      />
                      <button type="submit" class="w-full sm:w-auto neo-btn neo-btn-secondary text-sm sm:text-lg py-2 sm:py-3 px-6 sm:px-8">
                        <span>RAISE</span>
                      </button>
                    </div>
                    <div class="flex justify-between text-xs sm:text-sm text-gray-600 font-medium">
                      <span>MIN: <span class="neo-bitcoin">₿</span><%= @player_view.betting_info.min_raise %></span>
                      <span>MAX: <span class="neo-bitcoin">₿</span><%= @player_view.current_player.chips + (@player_view.betting_info.call_amount || 0) %></span>
                    </div>
                    <input type="hidden" name="action" value="raise" />
                  </form>
                </div>
              </div>
            </div>
          </div>

          <!-- Neo Wave Showdown Results -->
          <div :if={@player_view.showdown_results} class="mb-8">
            <div class="glass-neo p-6 border-2 border-yellow-400/50">
              <h3 class="text-2xl font-bold mb-6 text-center gradient-text">SHOWDOWN RESULTS</h3>
              
              <!-- Neo Wave Winner Announcement -->
              <%= for winner_id <- @player_view.showdown_results.winners do %>
                <div class="text-center mb-6">
                  <div class="text-3xl font-bold mb-2">
                    <span class="gradient-text">
                      <%= if winner_id == @current_player, do: "YOU WIN!", else: "#{String.upcase(winner_id)} WINS!" %>
                    </span>
                  </div>
                  <div class="text-lg text-gray-700 font-medium">
                    <%= @player_view.showdown_results.hand_descriptions[winner_id] %>
                  </div>
                  <div class="flex justify-center mt-3">
                    <span class="neo-club text-3xl">♣</span>
                    <span class="neo-diamond text-3xl">♦</span>
                    <span class="neo-heart text-3xl">♥</span>
                    <span class="neo-spade text-3xl">♠</span>
                  </div>
                </div>
              <% end %>
              
              <!-- Neo Wave Player Hands Display -->
              <div class="space-y-4">
                <%= for player <- @player_view.players do %>
                  <%= if length(player.hole_cards) > 0 do %>
                    <div class={"p-3 sm:p-4 rounded-2xl backdrop-blur " <>
                      if player.id in @player_view.showdown_results.winners do
                        "bg-green-500/20 border-2 border-green-400/50 shadow-lg shadow-green-400/20"
                      else
                        "bg-white/10 border border-white/30"
                      end}>
                      <!-- Mobile: Stack layout, Desktop: Side-by-side layout -->
                      <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center">
                        <!-- Player and cards section -->
                        <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4">
                          <!-- Player info -->
                          <div class="flex items-center gap-2 sm:gap-3 justify-center sm:justify-start">
                            <div class={"w-8 h-8 sm:w-10 sm:h-10 rounded-full flex items-center justify-center text-white font-bold text-sm sm:text-base " <>
                              if player.id in @player_view.showdown_results.winners do
                                "bg-gradient-to-br from-green-400 to-green-600"
                              else
                                "bg-gradient-to-br from-gray-400 to-gray-600"
                              end}>
                              <%= if player.is_current_player, do: "Y", else: String.first(player.id) |> String.upcase() %>
                            </div>
                            <span class="font-bold text-gray-900 text-base sm:text-lg">
                              <%= if player.is_current_player, do: "YOU", else: String.upcase(player.id) %>
                            </span>
                          </div>
                          <!-- Cards centered on mobile -->
                          <div class="flex gap-2 justify-center sm:justify-start">
                            <%= for card <- player.hole_cards do %>
                              <div class={"neo-card text-xs sm:text-sm " <> 
                                case card.color do
                                  "red-600" -> "pink-suit"
                                  "blue-600" -> "cyan-suit" 
                                  "green-600" -> "green-suit"
                                  "gray-900" -> "yellow-suit"
                                  _ -> "yellow-suit"
                                end}>
                                <%= card.display %>
                              </div>
                            <% end %>
                          </div>
                        </div>
                        <!-- Hand evaluation below cards on mobile, right side on desktop -->
                        <div class="text-gray-700 font-medium text-center sm:text-right text-sm sm:text-base mt-2 sm:mt-0">
                          <%= @player_view.showdown_results.hand_descriptions[player.id] %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <div :if={@player_view.can_start_hand}>
            <div class="glass-neo p-4 sm:p-6 text-center">
              <p class="mb-4 sm:mb-6 text-lg sm:text-xl font-bold">
                <span class="gradient-text">HAND COMPLETE!</span>
              </p>
              <p class="mb-4 sm:mb-6 text-gray-700 text-sm sm:text-base">Ready to deal the next hand?</p>
              <button 
                phx-click="start_hand" 
                class="neo-btn neo-btn-secondary text-sm sm:text-lg py-3 sm:py-4 px-6 sm:px-8">
                <span>DEAL NEXT HAND</span>
              </button>
            </div>
          </div>

          <!-- Neo Wave Game Complete Interface -->
          <div :if={@player_view.players && @player_view.phase == :hand_complete && length(Enum.filter(@player_view.players, &(&1.chips > 0))) == 1}>
            <div class="glass-neo p-4 sm:p-8 text-center border-2 border-green-400/50 relative overflow-hidden">
              <div class="absolute inset-0 bg-gradient-to-br from-green-400/10 to-cyan-400/10"></div>
              <div class="relative z-10">
                <h3 class="text-2xl sm:text-3xl font-bold mb-4 sm:mb-6">
                  <span class="gradient-text">GAME COMPLETE!</span>
                </h3>
                <div class="flex justify-center mb-4 sm:mb-6 gap-1 sm:gap-2">
                  <span class="neo-club text-2xl sm:text-4xl">♣</span>
                  <span class="neo-diamond text-2xl sm:text-4xl">♦</span>
                  <span class="neo-heart text-2xl sm:text-4xl">♥</span>
                  <span class="neo-spade text-2xl sm:text-4xl">♠</span>
                </div>
                <p class="mb-6 sm:mb-8 text-lg sm:text-xl text-gray-700">Ready for another round?</p>
                <button 
                  phx-click="play_again" 
                  class="neo-btn neo-btn-primary text-lg sm:text-xl py-3 sm:py-4 px-8 sm:px-10">
                  <span>PLAY AGAIN</span>
                </button>
              </div>
            </div>
          </div>

          <div :if={not @player_view.can_act and not @player_view.can_start_hand and not @player_view.is_waiting_for_players}>
            <% opponent = if length(@player_view.players) == 2, do: Enum.find(@player_view.players, &(not &1.is_current_player)) %>
            <div class="glass-neo p-4 sm:p-6 text-center">
              <div class="animate-pulse">
                <div class="flex justify-center mb-3 sm:mb-4">
                  <div class="w-6 h-6 sm:w-8 sm:h-8 bg-gradient-to-r from-pink-500 to-cyan-500 rounded-full animate-spin"></div>
                </div>
                <p class="text-gray-700 text-base sm:text-lg font-medium">
                  <%= if opponent do %>
                    Waiting for <span class="gradient-text font-bold"><%= String.upcase(opponent.id) %></span>...
                  <% else %>
                    Waiting for other players...
                  <% end %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Neo Wave Debug Info -->
      <div :if={@player_view != nil and show_debug?()} class="mt-6 glass-neo p-4">
        <details>
          <summary class="cursor-pointer font-bold text-gray-900 hover:text-cyan-600 transition-colors">DEBUG: Player View</summary>
          <pre class="mt-4 text-xs overflow-auto bg-gray-900/50 p-4 rounded-lg text-green-400 font-mono"><%= inspect(@player_view, pretty: true) %></pre>
        </details>
      </div>
    </div>
    """
  end
end
