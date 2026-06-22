"""
AI Engine router — chat, streaming chat, file analysis, insights, voice.
"""
import json
from typing import Annotated, AsyncGenerator
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse

from ..models.schemas import (
    ChatRequest, ChatResponse, ChatMessage,
    FileAnalysisRequest, InsightRequest,
)
from ..services.ai_service import AIService
from ..middleware.auth_middleware import get_current_user
from ..dependencies import get_erp_service
from ..services.erpnext_service import ERPNextService

router = APIRouter(prefix="/ai", tags=["ai"])


def _get_ai_service() -> AIService:
    return AIService()


@router.post("/chat", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    current_user: Annotated[dict, Depends(get_current_user)],
    ai: Annotated[AIService, Depends(_get_ai_service)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    if payload.stream:
        raise HTTPException(400, "Use /chat/stream for streaming responses")
    return await ai.chat(payload, current_user)


@router.post("/chat/stream")
async def chat_stream(
    payload: ChatRequest,
    current_user: Annotated[dict, Depends(get_current_user)],
    ai: Annotated[AIService, Depends(_get_ai_service)],
):
    async def _event_stream() -> AsyncGenerator[str, None]:
        async for chunk in ai.chat_stream(payload, current_user):
            yield f"data: {json.dumps({'delta': chunk})}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(_event_stream(), media_type="text/event-stream")


@router.post("/analyze-file")
async def analyze_file(
    file: UploadFile = File(...),
    context: str = Form(default=""),
    current_user: dict = Depends(get_current_user),
    ai: AIService = Depends(_get_ai_service),
):
    content = await file.read()
    result = await ai.analyze_file(
        file_content=content,
        file_name=file.filename or "file",
        file_type=file.content_type or "application/octet-stream",
        context=context,
        user=current_user,
    )
    return result


@router.post("/insights")
async def get_insights(
    payload: InsightRequest,
    current_user: Annotated[dict, Depends(get_current_user)],
    ai: Annotated[AIService, Depends(_get_ai_service)],
    erp: Annotated[ERPNextService, Depends(get_erp_service)],
):
    # Fetch ERP data to feed the insight engine
    data = await erp.get_list(
        doctype=payload.doctype,
        filters=payload.filters,
        limit=100,
    )
    return await ai.generate_insights(
        doctype=payload.doctype,
        data=data,
        period=payload.period or "last_30_days",
        user=current_user,
    )
