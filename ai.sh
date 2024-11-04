#!/bin/bash

# Aktivera debugläge om DEBUG miljövariabel är satt
[[ -n "$DEBUG" ]] && set -x

# Kontrollera om API-nyckeln är satt som miljövariabel
if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY miljövariabel är inte satt."
    echo "Lägg till följande i din ~/.bashrc eller ~/.zshrc:"
    echo "export OPENAI_API_KEY='din-nyckel-här'"
    exit 1
fi

# Kontrollera om jq är installerat
if ! command -v jq &> /dev/null; then
    echo "Error: jq är inte installerat. Installera det med:"
    echo "På macOS: brew install jq"
    echo "På Ubuntu/Debian: sudo apt install jq"
    exit 1
fi

# Samla alla argument till en sträng och escapea för JSON
QUERY=$(printf '%s' "$*" | jq -R -s '.')

# Kontrollera om vi har en fråga
if [ -z "$*" ]; then
    echo "Användning: @ai <din fråga här>"
    echo "Exempel: @ai hjälp mig att komprimera video.mp4"
    exit 1
fi

# Skapa JSON-payload för API-anropet
PAYLOAD=$(jq -n \
    --arg query "$*" \
    '{
        model: "gpt-4o-mini",
        messages: [
            {
                role: "system",
                content: "Du är en terminal-expert. Ge ENDAST kommandot som ett svar, utan förklaringar. Kommandot ska vara en one-liner som löser användarens problem. Välj rätt verktyg baserat på filtyp:

MEDIA:
- Video: Använd ffmpeg för videokomprimering, t.ex. '\''ffmpeg -i input.mp4 -c:v libx264 -crf 23 output.mp4'\''
- Bilder: Använd convert/imagemagick för bildoptimering, t.ex. '\''convert input.jpg -quality 85 output.jpg'\''
- Ljud: Använd ffmpeg för ljudkomprimering, t.ex. '\''ffmpeg -i input.wav -c:a aac output.m4a'\''

DOKUMENT & DATA:
- Stora filer/mappar: zip eller tar.gz beroende på behov
- Textfiler: gzip för enkelhet
- PDF: gs för PDF-optimering

REGLER:
- Bevara originalet när möjligt
- Välj kvalitetsnivå baserat på kontext
- Lägg till filtillägg som matchar komprimeringstekniken
- För bästa komprimering vs. snabb komprimering, välj passande flaggor

Om du är osäker, börja svaret med #OSÄKER# följt av kommandot."
            },
            {
                role: "user",
                content: "Ge mig ett terminalkommando för att: \($query)"
            }
        ],
        temperature: 0.7
    }')

# Visa payload om vi är i debugläge
if [[ -n "$DEBUG" ]]; then
    echo "API Payload:"
    echo "$PAYLOAD" | jq '.'
fi

# Gör API-anropet och spara hela svaret
FULL_RESPONSE=$(curl -s -w "\n%{http_code}" https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$PAYLOAD")

# Separera HTTP-statuskoden från svaret
HTTP_STATUS=$(echo "$FULL_RESPONSE" | tail -n1)
RESPONSE=$(echo "$FULL_RESPONSE" | sed '$d')

# Visa råa API-svaret om vi är i debugläge
if [[ -n "$DEBUG" ]]; then
    echo "HTTP Status: $HTTP_STATUS"
    echo "API Response:"
    echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
fi

# Kontrollera HTTP-status
if [ "$HTTP_STATUS" != "200" ]; then
    echo "Error: API-anropet misslyckades med status $HTTP_STATUS"
    echo "API svarade:"
    echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
    exit 1
fi

# Extrahera kommandot från svaret
COMMAND=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [ -z "$COMMAND" ] || [ "$COMMAND" = "null" ]; then
    echo "Error: Kunde inte extrahera kommandot från API-svaret"
    echo "Rått API-svar:"
    echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
    exit 1
fi

# Kontrollera om svaret är markerat som osäkert
if [[ $COMMAND == "#OSÄKER#"* ]]; then
    COMMAND=${COMMAND#"#OSÄKER#"}
    echo -e "\033[33mOBS: AI är inte helt säker på detta kommando. Var försiktig!\033[0m"
fi

# Visa kommandot och fråga användaren om de vill köra det
echo -e "\033[36mFöreslaget kommando:\033[0m"
echo "$COMMAND"
echo
read -p "Vill du köra detta kommando? (j/N) " answer

if [[ $answer =~ ^[Jj]$ ]]; then
    eval "$COMMAND"
else
    echo "Kommandot kördes inte."
    # Kopiera kommandot till urklipp om xclip finns installerat
    if command -v pbcopy &> /dev/null; then
        echo "$COMMAND" | pbcopy
        echo "Kommandot har kopierats till urklipp."
    elif command -v xclip &> /dev/null; then
        echo "$COMMAND" | xclip -selection clipboard
        echo "Kommandot har kopierats till urklipp."
    fi
fi
