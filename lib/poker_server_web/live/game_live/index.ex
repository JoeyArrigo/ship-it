defmodule PokerServerWeb.GameLive.Index do
  use PokerServerWeb, :live_view

  alias PokerServer.GameQueue
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(PokerServer.PubSub, "game_queue")
    end

    queue_status = GameQueue.get_status()

    socket =
      socket
      |> assign(:queue_status, queue_status)
      |> assign(:player_name, "")
      |> assign(:current_player, nil)
      |> assign(:in_queue, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Poker Server")
  end

  @impl true
  def handle_event("join_queue", %{"player_name" => raw_player_name}, socket) do
    player_name = String.trim(raw_player_name)
    
    cond do
      String.length(player_name) == 0 ->
        {:noreply, put_flash(socket, :error, "Player name cannot be empty")}
      
      String.length(player_name) > 40 ->
        {:noreply, put_flash(socket, :error, "Player name must be 40 characters or less")}
      
      true ->
        # Subscribe to personal notifications BEFORE joining queue
        if connected?(socket) do
          IO.puts("📢 Player #{player_name} subscribing to channel player:#{player_name}")
          PubSub.subscribe(PokerServer.PubSub, "player:#{player_name}")
        end

        case GameQueue.join_queue(player_name) do
          :ok ->
            {:noreply,
             socket
             |> assign(:current_player, player_name)
             |> assign(:in_queue, true)
             |> put_flash(:info, "Joined queue! Waiting for other players...")}

          {:error, :already_in_queue} ->
            {:noreply, put_flash(socket, :error, "You are already in the queue.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to join queue: #{reason}")}
        end
    end
  end

  def handle_event("leave_queue", _params, socket) do
    if socket.assigns.current_player do
      GameQueue.leave_queue(socket.assigns.current_player)
    end

    {:noreply,
     socket
     |> assign(:current_player, nil)
     |> assign(:in_queue, false)
     |> put_flash(:info, "Left the queue")}
  end

  @impl true
  def handle_info({:queue_updated, queue_state}, socket) do
    {:noreply, assign(socket, :queue_status, queue_state)}
  end

  @impl true
  def handle_info({:game_ready, game_id}, socket) do
    IO.puts("🎯 Player #{socket.assigns.current_player} received game_ready for game #{game_id}")
    player_name = socket.assigns.current_player
    {:noreply, push_navigate(socket, to: ~p"/game/#{game_id}?player=#{player_name}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto relative px-2 sm:px-4">
      <!-- Neo Wave floating particle effects -->
      <div class="neo-particles">
        <div class="neo-particle" style="left: 10%; animation-delay: 0s;"></div>
        <div class="neo-particle" style="left: 20%; animation-delay: 2s;"></div>
        <div class="neo-particle" style="left: 30%; animation-delay: 4s;"></div>
        <div class="neo-particle" style="left: 70%; animation-delay: 6s;"></div>
        <div class="neo-particle" style="left: 80%; animation-delay: 8s;"></div>
        <div class="neo-particle" style="left: 90%; animation-delay: 1s;"></div>
      </div>

      <!-- Neo Wave Hero Section -->
      <div class="text-center mb-8 sm:mb-12 relative">
        <div class="mb-6 sm:mb-8">
          <h1 class="text-4xl sm:text-6xl font-bold mb-4 logo-glitch gradient-text" data-text="SHIP•IT POKER">
            SHIP•IT POKER
          </h1>
          <div class="flex justify-center text-4xl sm:text-5xl gap-3 sm:gap-4 mb-6">
            <span class="neo-club">♣</span>
            <span class="neo-diamond">♦</span>
            <span class="neo-heart">♥</span>
            <span class="neo-spade">♠</span>
          </div>
          <p class="text-lg sm:text-xl text-gray-600 font-medium tracking-wider uppercase letter-spacing-2">
            SHORT DECK HOLD'EM • 36 CARDS • FLUSH BEATS FULL HOUSE
          </p>
        </div>
      </div>

      <!-- Neo Wave Queue Status -->
      <div class="mb-8 neo-table relative overflow-hidden">
        <div class="text-center">
          <h2 class="text-2xl sm:text-3xl font-bold mb-6 gradient-text">GAME LOBBY</h2>

          <!-- Players waiting display -->
          <div class="neo-pot mb-6">
            <div class="neo-pot-amount text-4xl sm:text-5xl">
              <%= length(@queue_status.waiting_players) %><span class="text-2xl sm:text-3xl">/2</span>
            </div>
            <div class="neo-pot-label">Players Ready</div>
          </div>

          <div class="glass-neo p-4 sm:p-6">
            <p class="text-gray-700 text-base sm:text-lg font-medium mb-2">
              Games launch automatically when 2 players join the queue
            </p>
            <p class="text-sm text-gray-600 font-medium">
              <strong>Short Deck:</strong> 36 cards (6-A), Ace still wraps (A-6-7-8-9 is low straight), Flush beats Full House
            </p>
            <div class="flex justify-center mt-4 gap-2">
              <span class="neo-club text-2xl">♣</span>
              <span class="neo-diamond text-2xl">♦</span>
              <span class="neo-heart text-2xl">♥</span>
              <span class="neo-spade text-2xl">♠</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Neo Wave Join Queue Form -->
      <div :if={not @in_queue} class="mb-8">
        <div class="glass-neo p-6 sm:p-8 relative overflow-hidden">
          <div class="absolute inset-0 bg-gradient-to-br from-pink-500/5 to-cyan-500/5"></div>
          <div class="relative z-10">
            <h2 class="text-xl sm:text-2xl font-bold mb-6 text-center gradient-text">JOIN THE ACTION</h2>

            <.simple_form phx-submit="join_queue" class="space-y-6">
              <div class="space-y-4">
                <label class="block text-sm font-bold text-gray-700 uppercase tracking-wider">
                  Player Name
                </label>
                <input
                  name="player_name"
                  type="text"
                  placeholder="Enter your name... 🎮"
                  required
                  maxlength="40"
                  class="w-full text-center bg-white/95 backdrop-blur border-2 border-cyan-400/50 rounded-2xl px-4 py-3 sm:py-4 text-lg sm:text-xl font-bold text-gray-900 placeholder-gray-400 focus:border-pink-500 focus:outline-none transition-colors"
                />
              </div>

              <div class="text-center">
                <button
                  type="submit"
                  class="neo-btn neo-btn-primary text-lg sm:text-xl py-4 px-8 sm:px-12">
                  <span>JOIN QUEUE</span>
                </button>
              </div>
            </.simple_form>
          </div>
        </div>
      </div>

      <!-- Neo Wave Waiting in Queue -->
      <div :if={@in_queue} class="mb-8">
        <div class="glass-neo p-6 sm:p-8 border-2 border-cyan-400/50 relative overflow-hidden">
          <div class="absolute inset-0 bg-gradient-to-br from-cyan-500/10 to-green-500/10"></div>
          <div class="relative z-10 text-center">
            <h2 class="text-xl sm:text-2xl font-bold mb-6 gradient-text">IN THE QUEUE</h2>

            <!-- Player status -->
            <div class="neo-avatar w-16 h-16 sm:w-20 sm:h-20 rounded-full mx-auto mb-4 text-2xl sm:text-3xl text-white font-bold flex items-center justify-center">
              <%= String.first(@current_player) |> String.upcase() %>
            </div>

            <div class="mb-6">
              <p class="text-lg sm:text-xl font-bold text-gray-900 mb-2">
                Welcome, <span class="gradient-text"><%= String.upcase(@current_player) %></span>!
              </p>
              <div class="neo-status active inline-block">
                Ready to Play
              </div>
            </div>

            <!-- Waiting animation -->
            <div class="mb-6">
              <div class="flex justify-center mb-4">
                <div class="w-8 h-8 sm:w-10 sm:h-10 bg-gradient-to-r from-pink-500 to-cyan-500 rounded-full animate-spin"></div>
              </div>
              <p class="text-gray-700 text-base sm:text-lg font-medium">
                Waiting for <%= 2 - length(@queue_status.waiting_players) %> more player(s)...
              </p>
            </div>

            <!-- Progress indicator -->
            <div class="mb-6">
              <div class="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
                <div
                  class="h-full bg-gradient-to-r from-pink-500 to-cyan-500 rounded-full transition-all duration-500"
                  style={"width: #{(length(@queue_status.waiting_players) / 2) * 100}%"}>
                </div>
              </div>
            </div>

            <button
              phx-click="leave_queue"
              class="neo-btn neo-btn-danger text-base sm:text-lg py-3 px-6 sm:px-8">
              <span>LEAVE QUEUE</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Neo Wave Feature Highlights -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
        <div class="glass-neo p-4 sm:p-6 text-center">
          <div class="text-3xl sm:text-4xl mb-3 neo-club">♣</div>
          <h3 class="font-bold text-gray-900 mb-2">Four-Color System</h3>
          <p class="text-sm text-gray-600">Revolutionary Neo Wave color-coded suits</p>
        </div>
        <div class="glass-neo p-4 sm:p-6 text-center">
          <div class="text-3xl sm:text-4xl mb-3 neo-diamond">♦</div>
          <h3 class="font-bold text-gray-900 mb-2">Instant Gameplay</h3>
          <p class="text-sm text-gray-600">Auto-matching with real-time action</p>
        </div>
        <div class="glass-neo p-4 sm:p-6 text-center sm:col-span-2 lg:col-span-1">
          <div class="text-3xl sm:text-4xl mb-3 neo-heart">♥</div>
          <h3 class="font-bold text-gray-900 mb-2">Next-Gen UX</h3>
          <p class="text-sm text-gray-600">Future-ready poker experience</p>
        </div>
      </div>

    </div>
    """
  end
end
