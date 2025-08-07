# Project Overview

This project is a mobile poker application built with Elixir and Phoenix on the backend and React Native on the frontend. The application focuses on providing a real-time, multiplayer experience for short deck hold'''em sit-n-go super-turbo tournaments. The backend is designed to be the authoritative source of game logic to prevent cheating, and it uses a WebSocket-based, event-driven architecture to communicate with the clients.

## Key Technologies

*   **Backend:** Elixir, Phoenix
*   **Frontend:** React Native, Expo
*   **Real-time Communication:** Phoenix Channels (WebSockets)
*   **Concurrency:** Elixir GenServers

## Architecture

The backend is built around a few key components:

*   **`PokerServer.GameServer`:** A `GenServer` that manages the state and logic for a single poker game. Each game runs in its own isolated process.
*   **`PokerServer.GameState`:** A struct that represents the state of a game, including players, cards, and pot size.
*   **`PokerServer.GameManager`:** A process that coordinates the creation and management of games.
*   **`PokerServer.GameQueue`:** A process that handles matchmaking and places players into games.
*   **`Phoenix.PubSub`:** Used for real-time communication between the server and the clients.
*   **`PokerServerWeb.Router`:** The main router for the Phoenix application, which uses Phoenix LiveView for the web interface.

# Building and Running

## Dependencies

To run the project, you will need to have Elixir and Erlang installed. You will also need to install the project'''s dependencies using `mix`:

```bash
mix deps.get
```

## Running the Application

To start the Phoenix server, run the following command:

```bash
mix phx.server
```

This will start the server on `http://localhost:4000`.

## Testing

To run the project'''s tests, use the following command:

```bash
mix test
```

# Development Conventions

*   **Server-Authoritative Logic:** All game logic is handled by the server to prevent cheating.
*   **Event-Driven Architecture:** The server communicates with the clients using a WebSocket-based, event-driven architecture.
*   **Isolated Game Processes:** Each poker game runs in its own isolated `GenServer` process to ensure that games do not interfere with each other.
*   **Phoenix LiveView:** The web interface is built using Phoenix LiveView.
