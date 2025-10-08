#!/usr/bin/env node
/**
 * Hermes JavaScript/Node.js Client Example
 *
 * Simple Node.js client for interacting with the Hermes LLM API.
 *
 * Usage:
 *     node javascript_client.js
 */

/**
 * Client for Hermes LLM API
 */
class HermesClient {
  /**
   * Create a Hermes client
   * @param {string} baseUrl - Base URL of the Hermes service
   */
  constructor(baseUrl = 'http://localhost:4020') {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  /**
   * Generate text completion from a model
   * @param {string} model - Name of the Ollama model (e.g., "gemma", "llama3")
   * @param {string} prompt - Text prompt to send to the model
   * @returns {Promise<Object>} Response with 'result' field
   * @throws {Error} If the request fails
   */
  async generate(model, prompt) {
    const url = `${this.baseUrl}/v1/llm/${model}`;
    const payload = { prompt };

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || `HTTP ${response.status}`);
    }

    return response.json();
  }

  /**
   * Get system health status
   * @returns {Promise<Object>} Status information
   * @throws {Error} If the request fails
   */
  async status() {
    const url = `${this.baseUrl}/v1/status`;
    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    return response.json();
  }
}

/**
 * Example usage of the Hermes client
 */
async function main() {
  // Initialize client
  const client = new HermesClient('http://localhost:4020');

  // Check system status
  console.log('Checking system status...');
  try {
    const status = await client.status();
    console.log(`✓ Status: ${status.status}`);
    console.log(`✓ Schedulers: ${status.schedulers}`);
    console.log(`✓ Total Memory: ${status.memory.total.toLocaleString()} bytes\n`);
  } catch (error) {
    console.error(`✗ Failed to get status: ${error.message}\n`);
    return;
  }

  // Generate text with Gemma model
  console.log('Generating text with Gemma model...');
  try {
    const result = await client.generate(
      'gemma',
      'What is Elixir programming language in one sentence?'
    );
    console.log(`✓ Response: ${result.result}\n`);
  } catch (error) {
    console.error(`✗ Error: ${error.message}\n`);
  }

  // Try with a different model
  console.log('Generating text with Llama3 model...');
  try {
    const result = await client.generate(
      'llama3',
      'Explain functional programming in one sentence.'
    );
    console.log(`✓ Response: ${result.result}\n`);
  } catch (error) {
    console.error(`✗ Error: ${error.message}\n`);
  }
}

// Run the example
main().catch(console.error);
