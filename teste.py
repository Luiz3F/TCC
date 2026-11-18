import warnings
from cryptography.utils import CryptographyDeprecationWarning
warnings.filterwarnings("ignore", category=CryptographyDeprecationWarning)

from scapy.all import rdpcap
import json
import argparse
from argparse import Namespace

def parse_arguments() -> Namespace:
    parser = argparse.ArgumentParser(description="Generates a script that creates and applies firewall rules to stop DoS attacks by using third-party LLMs")
    
    parser.add_argument("pcap_file", type=str, help="Path to the .pcap file that will be analysed")
    parser.add_argument("firewall", type=str, help="Firewall for which the rules will be generated")
    parser.add_argument("model", type=str, choices=["openai", "claude", "deepseek"], help="Model that will generate the script")
    parser.add_argument("-i", "--ip-agnostic", action="store_true", help="Script will create rules that are agnostic to attacker ip (in case of ip spoofing or something like that)")
    parser.add_argument("-a", "--attack", type=str, help="Type of DoS attack detected", default=None)

    return parser.parse_args()


# TODO: Verify if file size is bellow limit
def process_pcap(pcap_file_path: str) -> str:
    packets = rdpcap(pcap_file_path)

    json_list = [json.loads(packet.json()) for packet in packets]
    packets_string = json.dumps(json_list)

    return packets_string

def openai_response(input: str) -> str:
    from openai import OpenAI

    client = OpenAI()

    response = client.responses.create(
        model="gpt-6-luna",
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

def main():
    # Parse arguments
    args = parse_arguments()
    pcap_file = args.pcap_file
    firewall = args.firewall
    model = args.model
    ip_agnostic = args.ip_agnostic
    attack = args.attack

    # Process .pcap
    packets_string = process_pcap(pcap_file)

    # Send to LLM
    ip_agnostic_text = ("Make it so the rules will stop the attack even if the attacker changes their IP address" if ip_agnostic else "")
    attack_text = ("" if attack is None else f"{attack} ")

    input = f"""Use plaintext syntax. \
Make a sh script that generates and applies {firewall} firewall rules to stop the {attack_text}DoS attack detected in the following packet capture. \
Make the script and nothing else. {ip_agnostic_text}. \
{packets_string}"""

    response = ""
    match model:
        case "openai":
            response = openai_response(input)
        case "claude":
            response = claude_response(input)
        case "deepseek":
            # TODO
            response = "Not implemented"
        case _:
            response = "Should not be reached!!!"
            
    print(response)

if __name__ == "__main__":
    main()