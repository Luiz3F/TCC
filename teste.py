from scapy.all import rdpcap
import json

# TODO: Verify if file size is bellow limit
def process_pcap(pcap_file_path: str) -> str:
    packets = rdpcap(pcap_file_path)

    json_list = [json.loads(packet.json()) for packet in packets]
    packets_string = json.dumps(json_list)

    return packets_string

def gemini_response(packets_string: str) -> str:
    from google import genai

    client = genai.Client()

    interaction = client.interactions.create(
        model="gemini-3.6-flash",
        input=f"Use plaintext syntax. Generate firewall rules to stop the DoS attack detected in the following packet capture: {packets_string}"
    )

    return interaction.output_text

def main():
    packets_string = process_pcap("test_pcap\\test.pcap")
    response = gemini_response(packets_string)
    print(response)

if __name__ == "__main__":
    main()