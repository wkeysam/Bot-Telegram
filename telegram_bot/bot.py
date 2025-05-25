import logging
import os
import requests
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)


async def check_url_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text('Por favor, proporciona una URL después del comando. Ejemplo: /checkurl https://example.com')
        return

    url_to_check = context.args[0]
    message_text = f"Verificando URL: `{url_to_check}`\n"
    try:
    
        headers = {'User-Agent': 'OcasoSecurityBot/1.0'}
        response = requests.get(url_to_check, timeout=10, headers=headers, allow_redirects=True)
        message_text += f"Código de estado: `{response.status_code}`\n"
        
        if response.status_code == 200:
            message_text += " ¡URL accesible!"
        else:
            message_text += f" Problema al acceder a la URL. Razón: {response.reason}"
            
    except requests.exceptions.Timeout:
        message_text += " Error: La solicitud tardó demasiado tiempo (timeout)."
    except requests.exceptions.TooManyRedirects:
        message_text += " Error: Demasiadas redirecciones."
    except requests.exceptions.RequestException as e:
        message_text += f" Error al intentar conectar: {e}"
    
    await update.message.reply_text(message_text, parse_mode='MarkdownV2')

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    help_text = (
        "¡Hola! Soy el bot de Ocaso-Security.\n"
        "Comandos disponibles:\n"
        "/checkurl <URL> - Verifica el estado de una URL.\n"
        "/help - Muestra este mensaje de ayuda."
    )
    await update.message.reply_text(help_text)

def main() -> None:
    """Inicia el bot."""
    bot_token = os.getenv("TELEGRAM_BOT_TOKEN")
    if not bot_token:
        logger.error("No se encontró la variable de entorno TELEGRAM_BOT_TOKEN.")
        return

    application = Application.builder().token(bot_token).build()

    # Registra los manejadores de comandos
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", start_command)) # Reutiliza start para /help
    application.add_handler(CommandHandler("checkurl", check_url_command))

    logger.info("Iniciando el bot...")
    application.run_polling()

if __name__ == '__main__':
    main()