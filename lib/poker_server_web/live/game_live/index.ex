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
  def handle_event("join_queue", %{"player_name" => player_name}, socket) when byte_size(player_name) > 0 do
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

  def handle_event("join_queue", _params, socket) do
    {:noreply, put_flash(socket, :error, "Player name cannot be empty")}
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
    <div class="max-w-4xl mx-auto">
      <.header>
        Welcome to Poker Server
        <:subtitle>
          Join the queue to play poker with other players
        </:subtitle>
      </.header>

      <!-- Queue Status -->
      <div class="mt-8 bg-white rounded-lg shadow-md p-6 text-center">
        <h2 class="text-2xl font-semibold mb-4">Game Queue</h2>
        <div class="text-lg mb-6">
          <span class="text-gray-600">Players waiting:</span>
          <span class="font-bold text-blue-600 text-2xl ml-2"><%= length(@queue_status.waiting_players) %></span>
        </div>
        <p class="text-gray-600 mb-6">
          Games start automatically when 2 players are in the queue
        </p>
      </div>

      <!-- Join Queue Form -->
      <div :if={not @in_queue} class="mt-8 bg-white rounded-lg shadow-md p-6">
        <h2 class="text-xl font-semibold mb-4">Join Next Game</h2>
        <.simple_form phx-submit="join_queue">
          <.input
            name="player_name"
            type="text"
            label="Your Name"
            placeholder="Enter your name..."
            required
          />
          <:actions>
            <.button type="submit" class="bg-green-600 hover:bg-green-700">
              Join Queue
            </.button>
          </:actions>
        </.simple_form>
      </div>

      <!-- Waiting in Queue -->
      <div :if={@in_queue} class="mt-8 bg-blue-50 border border-blue-200 rounded-lg shadow-md p-6">
        <h2 class="text-xl font-semibold text-blue-800 mb-4 text-center">Waiting in Queue</h2>
        <div class="text-center">
          <p class="text-blue-700 mb-4">
            You're in the queue as: <strong><%= @current_player %></strong>
          </p>
          <p class="text-blue-600 mb-6">
            Waiting for <%= 2 - length(@queue_status.waiting_players) %> more player(s) to start the game...
          </p>
          <.button phx-click="leave_queue" class="bg-red-600 hover:bg-red-700">
            Leave Queue
          </.button>
        </div>
      </div>

    </div>
    """
  end
end