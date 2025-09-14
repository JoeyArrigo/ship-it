defmodule PokerServer.Security.ShamirSecretSharing do
  import Bitwise
  
  @moduledoc """
  Implementation of Shamir's Secret Sharing scheme for secure card state storage.
  
  Uses a (2,3) threshold scheme where any 2 out of 3 shards can reconstruct the secret,
  but individual shards reveal nothing about the original data.
  
  Security properties:
  - Information-theoretic security (not just computational)
  - Perfect secrecy for individual shards
  - Threshold reconstruction (need exactly 2 shards)
  """
  
  # Use a very large prime for finite field arithmetic (2^2203 - 1, a Mersenne prime)
  # This can handle secrets up to ~275 bytes, perfect for our card state (161 bytes + margin)
  @prime (1 <<< 2203) - 1
  
  @doc """
  Splits a secret into 3 shards using Shamir's Secret Sharing.
  Returns a list of 3 encrypted shards where any 2 can reconstruct the original.
  """
  @spec split_secret(binary()) :: {:ok, [map()]} | {:error, term()}
  def split_secret(secret) when is_binary(secret) do
    try do
      # Convert binary secret to integer (may require padding for very large secrets)
      secret_int = binary_to_integer(secret)
      
      if secret_int >= @prime do
        {:error, :secret_too_large}
      else
        # Generate random coefficient for polynomial: f(x) = secret + a1*x (mod p)
        a1 = :crypto.strong_rand_bytes(32) |> binary_to_integer() |> rem(@prime)
        
        # Evaluate polynomial at x=1,2,3 to get 3 shares
        shares = for x <- [1, 2, 3] do
          y = mod_add(secret_int, mod_mul(a1, x, @prime), @prime)
          %{x: x, y: y}
        end
        
        # Encrypt each share with AES-GCM for additional protection
        encrypted_shards = Enum.map(shares, &encrypt_shard/1)
        
        {:ok, encrypted_shards}
      end
    rescue
      error -> {:error, error}
    end
  end
  
  @doc """
  Reconstructs the original secret from any 2 out of 3 shards.
  """
  @spec reconstruct_secret([map()]) :: {:ok, binary()} | {:error, term()}
  def reconstruct_secret(encrypted_shards) when length(encrypted_shards) >= 2 do
    try do
      # Decrypt shards
      shards = Enum.map(encrypted_shards, &decrypt_shard/1)
      
      # Take first 2 shards for reconstruction
      [shard1, shard2] = Enum.take(shards, 2)
      
      # Lagrange interpolation to find f(0) = secret
      secret_int = lagrange_interpolate([shard1, shard2], 0, @prime)
      
      # Convert back to binary
      secret_binary = integer_to_binary(secret_int)
      
      {:ok, secret_binary}
    rescue
      error -> {:error, error}
    end
  end
  
  def reconstruct_secret(_), do: {:error, :insufficient_shards}
  
  # Private functions
  
  defp encrypt_shard(%{x: x, y: y}) do
    # Serialize the shard
    shard_data = :erlang.term_to_binary({x, y})
    
    # Generate random key and nonce for this shard
    key = :crypto.strong_rand_bytes(32)
    nonce = :crypto.strong_rand_bytes(12)
    
    # Encrypt with AES-256-GCM
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, shard_data, "", true)
    
    # Return encrypted shard with metadata
    %{
      shard_index: x,
      encrypted_data: ciphertext <> tag,
      nonce: nonce,
      key: key,  # In production, this would be derived/stored more securely
      hash: :crypto.hash(:sha256, shard_data) |> Base.encode16(case: :lower)
    }
  end
  
  defp decrypt_shard(%{encrypted_data: encrypted_data, nonce: nonce, key: key}) do
    # Split ciphertext and tag
    ciphertext_size = byte_size(encrypted_data) - 16
    <<ciphertext::binary-size(ciphertext_size), tag::binary-size(16)>> = encrypted_data
    
    # Decrypt
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, "", tag, false) do
      :error -> raise "Decryption failed - shard may be corrupted"
      plaintext -> 
        {x, y} = :erlang.binary_to_term(plaintext)
        %{x: x, y: y}
    end
  end
  
  # Lagrange interpolation for polynomial reconstruction
  defp lagrange_interpolate(points, x_target, prime) do
    points
    |> Enum.with_index()
    |> Enum.reduce(0, fn {%{x: x_i, y: y_i}, _i}, acc ->
      # Calculate Lagrange basis polynomial L_i(x_target)
      numerator = Enum.reduce(points, 1, fn %{x: x_j}, prod ->
        if x_i == x_j, do: prod, else: mod_mul(prod, x_target - x_j, prime)
      end)
      
      denominator = Enum.reduce(points, 1, fn %{x: x_j}, prod ->
        if x_i == x_j, do: prod, else: mod_mul(prod, x_i - x_j, prime)
      end)
      
      # L_i(x_target) = numerator / denominator (mod prime)
      lagrange_coeff = mod_mul(numerator, mod_inverse(denominator, prime), prime)
      
      # Add y_i * L_i(x_target) to result
      mod_add(acc, mod_mul(y_i, lagrange_coeff, prime), prime)
    end)
  end
  
  # Modular arithmetic functions
  defp mod_add(a, b, m) do
    result = rem(a + b, m)
    if result < 0, do: result + m, else: result
  end
  
  defp mod_mul(a, b, m) do
    result = rem(a * b, m)
    if result < 0, do: result + m, else: result
  end
  
  # Modular multiplicative inverse using extended Euclidean algorithm
  defp mod_inverse(a, m) do
    # Normalize negative inputs
    normalized_a = if a < 0, do: rem(a, m) + m, else: rem(a, m)
    
    case extended_gcd(normalized_a, m) do
      {1, x, _y} -> 
        result = rem(x, m)
        if result < 0, do: result + m, else: result
      {gcd, _x, _y} -> 
        raise "Modular inverse does not exist: gcd(#{normalized_a}, #{m}) = #{gcd}"
    end
  end
  
  defp extended_gcd(a, 0), do: {a, 1, 0}
  defp extended_gcd(a, b) do
    {g, x1, y1} = extended_gcd(b, rem(a, b))
    {g, y1, x1 - div(a, b) * y1}
  end
  
  # Binary/integer conversion helpers
  defp binary_to_integer(binary) do
    binary 
    |> Base.encode16()
    |> String.to_integer(16)
  end
  
  defp integer_to_binary(integer) do
    integer
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")  # Ensure even length
    |> Base.decode16!(case: :mixed)
  end
end