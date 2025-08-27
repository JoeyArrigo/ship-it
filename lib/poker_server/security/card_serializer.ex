defmodule PokerServer.Security.CardSerializer do
  @moduledoc """
  Efficient serialization/deserialization of card state for secure storage.
  
  Uses a tuple lookup table to convert Card structs to integers 0-35,
  dramatically reducing storage size from ~68 bytes per card to ~3 bytes per card (95%+ reduction).
  
  The lookup table maps positions 0-35 to cards in short deck poker (6-Ace, 4 suits).
  Cards are ordered by rank (6-A) then suit (clubs, diamonds, hearts, spades).
  """
  
  alias PokerServer.Card
  
  # Lookup tuple: position 0-35 maps to specific cards
  # Ordered by rank (6,7,8,9,10,J,Q,K,A) then suit (clubs,diamonds,hearts,spades)
  @card_lookup {
    # 6s (0-3)
    %Card{rank: :six, suit: :clubs},
    %Card{rank: :six, suit: :diamonds}, 
    %Card{rank: :six, suit: :hearts},
    %Card{rank: :six, suit: :spades},
    
    # 7s (4-7)
    %Card{rank: :seven, suit: :clubs},
    %Card{rank: :seven, suit: :diamonds},
    %Card{rank: :seven, suit: :hearts}, 
    %Card{rank: :seven, suit: :spades},
    
    # 8s (8-11)
    %Card{rank: :eight, suit: :clubs},
    %Card{rank: :eight, suit: :diamonds},
    %Card{rank: :eight, suit: :hearts},
    %Card{rank: :eight, suit: :spades},
    
    # 9s (12-15)
    %Card{rank: :nine, suit: :clubs},
    %Card{rank: :nine, suit: :diamonds},
    %Card{rank: :nine, suit: :hearts},
    %Card{rank: :nine, suit: :spades},
    
    # 10s (16-19)
    %Card{rank: :ten, suit: :clubs},
    %Card{rank: :ten, suit: :diamonds},
    %Card{rank: :ten, suit: :hearts},
    %Card{rank: :ten, suit: :spades},
    
    # Jacks (20-23)
    %Card{rank: :jack, suit: :clubs},
    %Card{rank: :jack, suit: :diamonds},
    %Card{rank: :jack, suit: :hearts},
    %Card{rank: :jack, suit: :spades},
    
    # Queens (24-27)
    %Card{rank: :queen, suit: :clubs},
    %Card{rank: :queen, suit: :diamonds},
    %Card{rank: :queen, suit: :hearts},
    %Card{rank: :queen, suit: :spades},
    
    # Kings (28-31)
    %Card{rank: :king, suit: :clubs},
    %Card{rank: :king, suit: :diamonds},
    %Card{rank: :king, suit: :hearts},
    %Card{rank: :king, suit: :spades},
    
    # Aces (32-35)
    %Card{rank: :ace, suit: :clubs},
    %Card{rank: :ace, suit: :diamonds},
    %Card{rank: :ace, suit: :hearts},
    %Card{rank: :ace, suit: :spades}
  }
  
  # Reverse lookup map: Card -> index (built at compile time)
  @index_lookup @card_lookup
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Map.new(fn {card, index} -> {card, index} end)
  
  @doc """
  Converts card state to compact integer representation for efficient storage.
  
  ## Parameters
  - card_state: Map containing hole_cards, community_cards, and deck
  
  ## Returns
  - Compact representation where all cards are integers 0-35
  """
  @spec serialize_card_state(map()) :: map()
  def serialize_card_state(card_state) do
    %{
      hole_cards: serialize_hole_cards(card_state.hole_cards),
      community_cards: Enum.map(card_state.community_cards, &card_to_index/1),
      deck: Enum.map(card_state.deck, &card_to_index/1)
    }
  end
  
  @doc """
  Converts compact integer representation back to Card structs.
  
  ## Parameters  
  - compact_state: Map with integer representations of cards (0-35)
  
  ## Returns
  - Full card state with Card structs
  """
  @spec deserialize_card_state(map()) :: map()
  def deserialize_card_state(compact_state) do
    %{
      hole_cards: deserialize_hole_cards(compact_state.hole_cards),
      community_cards: Enum.map(compact_state.community_cards, &index_to_card/1),
      deck: Enum.map(compact_state.deck, &index_to_card/1)
    }
  end
  
  @doc """
  Converts a Card struct to its lookup table index (0-35).
  """
  @spec card_to_index(Card.t()) :: integer()
  def card_to_index(card) do
    case Map.get(@index_lookup, card) do
      nil -> raise ArgumentError, "Invalid card for short deck: #{inspect(card)}"
      index -> index
    end
  end
  
  @doc """
  Converts a lookup table index (0-35) back to a Card struct.
  """
  @spec index_to_card(integer()) :: Card.t()
  def index_to_card(index) when index >= 0 and index <= 35 do
    elem(@card_lookup, index)
  end
  
  def index_to_card(index) do
    raise ArgumentError, "Card index must be 0-35, got: #{index}"
  end
  
  # Private helper functions
  
  defp serialize_hole_cards(hole_cards) do
    Map.new(hole_cards, fn {player_id, cards} ->
      {player_id, Enum.map(cards, &card_to_index/1)}
    end)
  end
  
  defp deserialize_hole_cards(compact_hole_cards) do
    Map.new(compact_hole_cards, fn {player_id, card_indices} ->
      {player_id, Enum.map(card_indices, &index_to_card/1)}
    end)
  end
  
  @doc """
  Returns the lookup table for debugging/testing purposes.
  """
  @spec get_lookup_table() :: tuple()
  def get_lookup_table, do: @card_lookup
  
  @doc """
  Validates that all cards in a card state are valid short deck cards.
  """
  @spec validate_card_state(map()) :: :ok | {:error, term()}
  def validate_card_state(card_state) do
    try do
      # Test serialization - will raise if any invalid cards
      _compact = serialize_card_state(card_state)
      :ok
    rescue
      e in ArgumentError -> {:error, e.message}
    end
  end
end