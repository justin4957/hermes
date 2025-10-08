#!/usr/bin/env python3
"""
Hermes Python Client Example

Simple Python client for interacting with the Hermes LLM API.

Requirements:
    pip install requests

Usage:
    python python_client.py
"""

import requests
import json
from typing import Optional, Dict, Any


class HermesClient:
    """Client for Hermes LLM API."""

    def __init__(self, base_url: str = "http://localhost:4020"):
        """
        Initialize Hermes client.

        Args:
            base_url: Base URL of the Hermes service
        """
        self.base_url = base_url.rstrip("/")

    def generate(self, model: str, prompt: str) -> Dict[str, Any]:
        """
        Generate text completion from a model.

        Args:
            model: Name of the Ollama model (e.g., "gemma", "llama3")
            prompt: Text prompt to send to the model

        Returns:
            Dictionary with 'result' key containing generated text

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/v1/llm/{model}"
        payload = {"prompt": prompt}

        response = requests.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=60
        )

        response.raise_for_status()
        return response.json()

    def status(self) -> Dict[str, Any]:
        """
        Get system health status.

        Returns:
            Dictionary with status, memory, and scheduler information

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/v1/status"
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.json()


def main():
    """Example usage of the Hermes client."""
    # Initialize client
    client = HermesClient("http://localhost:4020")

    # Check system status
    print("Checking system status...")
    try:
        status = client.status()
        print(f"✓ Status: {status['status']}")
        print(f"✓ Schedulers: {status['schedulers']}")
        print(f"✓ Total Memory: {status['memory']['total']:,} bytes\n")
    except requests.RequestException as e:
        print(f"✗ Failed to get status: {e}\n")
        return

    # Generate text with Gemma model
    print("Generating text with Gemma model...")
    try:
        result = client.generate(
            model="gemma",
            prompt="What is Elixir programming language in one sentence?"
        )
        print(f"✓ Response: {result['result']}\n")
    except requests.HTTPError as e:
        if e.response.status_code == 400:
            error = e.response.json()
            print(f"✗ Bad request: {error['error']}\n")
        elif e.response.status_code == 500:
            error = e.response.json()
            print(f"✗ Server error: {error['error']}\n")
        else:
            print(f"✗ HTTP error: {e}\n")
    except requests.RequestException as e:
        print(f"✗ Request failed: {e}\n")

    # Try with a different model
    print("Generating text with Llama3 model...")
    try:
        result = client.generate(
            model="llama3",
            prompt="Explain functional programming in one sentence."
        )
        print(f"✓ Response: {result['result']}\n")
    except requests.HTTPError as e:
        error = e.response.json()
        print(f"✗ Error: {error.get('error', 'Unknown error')}\n")
    except requests.RequestException as e:
        print(f"✗ Request failed: {e}\n")


if __name__ == "__main__":
    main()
