# LiteLLM-Hook: Anbieter ohne Structured Outputs (response_format "json_schema") bekommen
# stattdessen "json_object", das Schema steht dann als Anweisung im System-Prompt.
# Beispiel: Mealie schickt json_schema, DeepSeek kennt nur json_object
# ("This response_format type is unavailable now"). Eingebunden in containers/litellm.nix.
import json

from litellm.integrations.custom_logger import CustomLogger

# Modell-Praefixe (wie der Client sie anfragt), fuer die umgeschrieben wird
PREFIXES = ("deepseek/",)


class JsonSchemaFallback(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        rf = data.get("response_format")
        model = str(data.get("model", ""))
        if not (isinstance(rf, dict) and rf.get("type") == "json_schema" and model.startswith(PREFIXES)):
            return data

        schema = (rf.get("json_schema") or {}).get("schema", {})
        hint = (
            "Antworte ausschliesslich mit einem gueltigen JSON-Objekt (json), ohne Markdown oder Text drumherum, "
            "das genau diesem JSON-Schema entspricht:\n" + json.dumps(schema, ensure_ascii=False)
        )
        messages = list(data.get("messages") or [])
        if messages and messages[0].get("role") == "system" and isinstance(messages[0].get("content"), str):
            messages[0] = {**messages[0], "content": messages[0]["content"] + "\n\n" + hint}
        else:
            messages.insert(0, {"role": "system", "content": hint})
        data["messages"] = messages
        data["response_format"] = {"type": "json_object"}
        return data


proxy_handler_instance = JsonSchemaFallback()
