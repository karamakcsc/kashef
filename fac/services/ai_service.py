"""
AI Service — multi-provider (Anthropic / OpenAI) with ERP context injection.
"""
import base64
import json
from typing import Any, AsyncGenerator
import anthropic
import openai
from ..models.schemas import (
    AIProvider, ChatMessage, ChatRequest, ChatResponse,
)
from ..config import get_settings

settings = get_settings()

_ERP_SYSTEM_PROMPT = """You are KCSC AI — an intelligent assistant embedded inside an ERPNext ERP system.
You help users:
- Query and analyse ERP data (Sales, Purchase, Inventory, HR, Finance)
- Trigger ERP workflows and actions
- Extract insights from documents and reports
- Answer questions about business operations

When the user asks to perform an ERP action, respond with a JSON block in this format:
<erp_action>
{"action": "create|update|delete|submit|get_list", "doctype": "...", "data": {...}}
</erp_action>

Always be concise, professional, and data-driven."""


class AIService:
    def __init__(self):
        self._anthropic = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        self._openai = openai.AsyncOpenAI(api_key=settings.openai_api_key)

    # ── Chat ──────────────────────────────────────────────────────────────────

    async def chat(self, request: ChatRequest, user: dict) -> ChatResponse:
        system = _ERP_SYSTEM_PROMPT
        if request.erp_context:
            system += f"\n\nERP Context:\n{json.dumps(request.erp_context, indent=2)}"

        model = request.model or settings.default_ai_model

        if request.provider == AIProvider.anthropic:
            return await self._anthropic_chat(request, system, model)
        return await self._openai_chat(request, system, model)

    async def _anthropic_chat(
        self, request: ChatRequest, system: str, model: str
    ) -> ChatResponse:
        messages = [{"role": m.role, "content": m.content} for m in request.messages]
        response = await self._anthropic.messages.create(
            model=model,
            max_tokens=request.max_tokens,
            system=system,
            messages=messages,
        )
        content = response.content[0].text
        erp_actions = self._extract_erp_actions(content)
        return ChatResponse(
            message=ChatMessage(role="assistant", content=content),
            provider="anthropic",
            model=model,
            usage={
                "input_tokens": response.usage.input_tokens,
                "output_tokens": response.usage.output_tokens,
            },
            erp_actions=erp_actions,
        )

    async def _openai_chat(
        self, request: ChatRequest, system: str, model: str
    ) -> ChatResponse:
        messages = [{"role": "system", "content": system}]
        messages += [{"role": m.role, "content": m.content} for m in request.messages]
        response = await self._openai.chat.completions.create(
            model=model or "gpt-4o",
            messages=messages,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
        )
        content = response.choices[0].message.content or ""
        erp_actions = self._extract_erp_actions(content)
        return ChatResponse(
            message=ChatMessage(role="assistant", content=content),
            provider="openai",
            model=model or "gpt-4o",
            usage={
                "input_tokens": response.usage.prompt_tokens,
                "output_tokens": response.usage.completion_tokens,
            },
            erp_actions=erp_actions,
        )

    # ── Streaming ─────────────────────────────────────────────────────────────

    async def chat_stream(
        self, request: ChatRequest, user: dict
    ) -> AsyncGenerator[str, None]:
        system = _ERP_SYSTEM_PROMPT
        model = request.model or settings.default_ai_model
        messages = [{"role": m.role, "content": m.content} for m in request.messages]

        if request.provider == AIProvider.anthropic:
            async with self._anthropic.messages.stream(
                model=model,
                max_tokens=request.max_tokens,
                system=system,
                messages=messages,
            ) as stream:
                async for text in stream.text_stream:
                    yield text
        else:
            stream = await self._openai.chat.completions.create(
                model=model or "gpt-4o",
                messages=[{"role": "system", "content": system}] + messages,
                stream=True,
            )
            async for chunk in stream:
                delta = chunk.choices[0].delta.content
                if delta:
                    yield delta

    # ── File Analysis ─────────────────────────────────────────────────────────

    async def analyze_file(
        self,
        file_content: bytes,
        file_name: str,
        file_type: str,
        context: str,
        user: dict,
    ) -> dict:
        prompt = f"Analyze this file: {file_name}. Context: {context or 'general analysis'}"

        if file_type.startswith("image/"):
            b64 = base64.standard_b64encode(file_content).decode()
            response = await self._anthropic.messages.create(
                model=settings.default_ai_model,
                max_tokens=2048,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "image", "source": {"type": "base64", "media_type": file_type, "data": b64}},
                        {"type": "text", "text": prompt},
                    ],
                }],
            )
            return {"analysis": response.content[0].text, "file_name": file_name}

        # PDF / text — extract text first
        text = await self._extract_text(file_content, file_type, file_name)
        response = await self._anthropic.messages.create(
            model=settings.default_ai_model,
            max_tokens=4096,
            system=_ERP_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": f"{prompt}\n\nFile content:\n{text[:12000]}"}],
        )
        return {"analysis": response.content[0].text, "file_name": file_name}

    async def _extract_text(self, content: bytes, file_type: str, file_name: str) -> str:
        if "pdf" in file_type or file_name.endswith(".pdf"):
            import io
            import PyPDF2
            reader = PyPDF2.PdfReader(io.BytesIO(content))
            return "\n".join(page.extract_text() or "" for page in reader.pages)
        if "spreadsheet" in file_type or file_name.endswith((".xlsx", ".xls")):
            import io
            import pandas as pd
            df = pd.read_excel(io.BytesIO(content))
            return df.to_string(max_rows=200)
        return content.decode("utf-8", errors="replace")

    # ── Insights ──────────────────────────────────────────────────────────────

    async def generate_insights(
        self, doctype: str, data: list, period: str, user: dict
    ) -> dict:
        prompt = (
            f"Analyze this {doctype} data for the period {period} and provide:\n"
            "1. Key metrics and KPIs\n"
            "2. Trends and patterns\n"
            "3. Anomalies or concerns\n"
            "4. Actionable recommendations\n\n"
            f"Data ({len(data)} records):\n{json.dumps(data[:50], indent=2)}"
        )
        response = await self._anthropic.messages.create(
            model=settings.default_ai_model,
            max_tokens=2048,
            system=_ERP_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )
        return {
            "doctype": doctype,
            "period": period,
            "record_count": len(data),
            "insights": response.content[0].text,
        }

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _extract_erp_actions(text: str) -> list[dict[str, Any]]:
        import re
        actions = []
        pattern = r"<erp_action>(.*?)</erp_action>"
        for match in re.finditer(pattern, text, re.DOTALL):
            try:
                actions.append(json.loads(match.group(1).strip()))
            except json.JSONDecodeError:
                pass
        return actions
