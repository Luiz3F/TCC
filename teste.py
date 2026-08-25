def gemini_response() -> str:
    from google import genai

    client = genai.Client()

    interaction = client.interactions.create(
        model="gemini-3.6-flash",
        input="Use plaintext syntax. Can you generate firewall rules based on a .csv file from wireshark??"
    )

    return interaction.output_text

def main():
    a = gemini_response()
    print(a)

if __name__ == "__main__":
    main()