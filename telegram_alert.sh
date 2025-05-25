#!/bin/bash

# Config
BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
REGION="eu-north-1"
PROFILE="sediaz"

echo "[INFO] Bot de Telegram arrancado..."

get_instance_id() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=Ocaso-Server" "Name=instance-state-name,Values=running" \
    --profile "$PROFILE" --region "$REGION" \
    --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null
}

get_lambda_name() {
  aws lambda list-functions \
    --query "Functions[?contains(FunctionName, 'Ocaso')].FunctionName" \
    --region "$REGION" --profile "$PROFILE" \
    --output text | head -n 1
}

send_message() {
  local text_content="$1"
  
  local encoded_text=$(printf %s "$text_content" | jq -sRr @uri)
  curl -s -X POST "$API_URL/sendMessage" -d chat_id="$CHAT_ID" -d text="$encoded_text" -d parse_mode="MarkdownV2" # Opcional: parse_mode si usas Markdown
}

while true; do
  
  UPDATES=$(curl -s "$API_URL/getUpdates?offset=-1&limit=1")
  
  
  MESSAGE_TEXT=$(echo "$UPDATES" | jq -r '.result[0].message.text')
  UPDATE_ID=$(echo "$UPDATES" | jq -r '.result[0].update_id')

  
  if [[ "$MESSAGE_TEXT" != "null" && ! -z "$MESSAGE_TEXT" ]]; then
    echo "Mensaje recibido: $MESSAGE_TEXT" 

    case "$MESSAGE_TEXT" in
      "/start")
        send_message "¡Hola! Soy el bot de control de Ocaso. Comandos disponibles:\n\n/estado – Ver recursos activos\n/apagar – Apagar EC2 y Lambda\n/checkurl <URL> – Verificar estado de una URL\n/help – Ayuda"
        ;;
      "/estado")
        INSTANCE_ID=$(get_instance_id)
        LAMBDA_NAME=$(get_lambda_name)
        send_message "Estado actual:\nEC2: \`${INSTANCE_ID:-No activa}\`\nLambda: \`${LAMBDA_NAME:-No encontrada}\`"
        ;;
      "/apagar")
        INSTANCE_ID=$(get_instance_id)
        LAMBDA_NAME=$(get_lambda_name)
        response_message=""

        if [[ "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "" ]]; then
          aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE"
          response_message+="EC2 (\`$INSTANCE_ID\`) detenida.\n"
        else
          response_message+="No se encontró instancia EC2 activa con tag Ocaso-Server.\n"
        fi

        if [[ "$LAMBDA_NAME" != "" ]]; then
          aws lambda update-function-configuration --function-name "$LAMBDA_NAME" \
            --region "$REGION" --profile "$PROFILE" --no-cli-pager --cli-read-timeout 60 --cli-connect-timeout 60 --enabled false
            # Añadido --no-cli-pager y timeouts para AWS CLI v2
          response_message+="Lambda (\`$LAMBDA_NAME\`) desactivada temporalmente."
        else
          response_message+="No se encontró ninguna Lambda Ocaso activa."
        fi
        send_message "$response_message"
        ;;
      "/help")
        send_message "ℹ Comandos disponibles:\n/start\n/estado\n/apagar\n/checkurl <URL>"
        ;;
      "/checkurl "*) 
        URL_TO_CHECK=$(echo "$MESSAGE_TEXT" | cut -d ' ' -f2-) # Captura todo después del primer espacio
        if [[ -z "$URL_TO_CHECK" || "$URL_TO_CHECK" == "/checkurl" ]]; then
          send_message "Por favor, proporciona una URL. Ejemplo: /checkurl https://example.com"
        else
          # Validar si es una URL (básico)
          if [[ "$URL_TO_CHECK" =~ ^https?:// ]]; then
            send_message "Verificando \`$URL_TO_CHECK\` ..."
           
            HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -L --max-time 10 "$URL_TO_CHECK")
            send_message "Respuesta para \`$URL_TO_CHECK\`:\nCódigo de estado: \`$HTTP_STATUS\`"
          else
            send_message "La URL proporcionada no parece válida. Asegúrate de que empiece con http:// o https://"
          fi
        fi
        ;;
      *) 
        echo "Comando no procesado o no reconocido: $MESSAGE_TEXT"
        ;;
    esac

    if [[ ! -z "$UPDATE_ID" && "$UPDATE_ID" != "null" ]]; then
        NEXT_OFFSET=$((UPDATE_ID + 1))
        curl -s "$API_URL/getUpdates?offset=$NEXT_OFFSET&limit=1" > /dev/null # Marcar como leído
    fi
  fi

  sleep 5
done
