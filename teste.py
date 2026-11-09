import warnings
from cryptography.utils import CryptographyDeprecationWarning
warnings.filterwarnings("ignore", category=CryptographyDeprecationWarning)

from scapy.all import rdpcap
import json
import sys

# TODO: Verify if file size is bellow limit
def process_pcap(pcap_file_path: str) -> str:
    packets = rdpcap(pcap_file_path)

    json_list = [json.loads(packet.json()) for packet in packets]
    packets_string = json.dumps(json_list)

    return packets_string

def gemini_response(input: str) -> str:
    from google import genai

    client = genai.Client()

    response = client.interactions.create(
        model="gemini-3.6-flash",
        input=input
    )

    return response.output_text

def openai_response(input: str) -> str:
    from openai import OpenAI

    client = OpenAI()

    response = client.responses.create(
        model="gpt-5.6-luna",
        input=input
    )

    return response.output_text

def claude_response(input: str) -> str:
    import anthropic

    client = anthropic.Anthropic()

    response = client.messages.create(
        max_tokens=10240,
        model="claude-sonnet-5",
        messages=[
            {
                "content": input,
                "role": "user",
            }
        ]
    )

    output = "".join(block.text for block in response.content if block.type == "text")
    return output

#TODO: deepseek_response

def main():
    pcap_file = sys.argv[1]
    packets_string = process_pcap(pcap_file)
    input = f"Use plaintext syntax. Make a sh script that generates and applies pfSense firewall rules to stop the DoS attack detected in the following packet capture. Make the script and nothing else. {packets_string}"
    response = openai_response(input)
    print(response)

if __name__ == "__main__":
    main()