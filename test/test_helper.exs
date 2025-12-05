ExUnit.start()

# Configure Mox for concurrent tests
Mox.defmock(Hermes.OllamaMock, for: Hermes.OllamaBehaviour)

# Make Mox available globally
Application.put_env(:hermes, :ollama_module, Hermes.OllamaMock)
