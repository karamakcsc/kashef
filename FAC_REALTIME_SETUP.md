# FAC Realtime Workflow Setup

Add these two code snippets to your FAC custom Frappe app to emit
`workflow_update` events that the Flutter app listens to.

---

## 1. `hooks.py`

Add a doc_event hook on `Workflow Action`:

```python
doc_events = {
    # ... your existing hooks ...
    "Workflow Action": {
        "on_update": "fac.api.on_workflow_action_update",
    },
}
```

---

## 2. `fac/api.py` (or wherever your API methods live)

```python
import frappe


def on_workflow_action_update(doc, method):
    """Emit realtime event when a Workflow Action is resolved."""
    # Only fire when the action moves out of Open state
    if doc.status == "Open":
        return

    frappe.publish_realtime(
        event="workflow_update",
        message={
            "user": doc.user,
            "reference_doctype": doc.reference_doctype,
            "reference_name": doc.reference_name,
            "new_state": doc.workflow_state,
            # 'action' is intentionally omitted here — it is set by
            # DocumentViewerPage.broadcastLocal() on the Flutter side.
        },
        user=doc.user,       # Only the approver receives this event
        after_commit=True,   # Fire after the DB transaction commits
    )
```

---

## How it works

```
Flutter: DocumentViewerPage.executeAction()
  → POST frappe.model.workflow.apply_workflow
    → Frappe updates Workflow Action.status = "Approved/Rejected"
      → on_workflow_action_update fires
        → frappe.publish_realtime("workflow_update", user=approver)
          → Flutter socket receives event
            → PendingApprovalsPage removes the item instantly
            → Drawer badge decrements
            → AI Chat shows confirmation bubble (if doc was opened from chat)

Flutter fallback (if socket unavailable):
  → RealtimeWorkflowService polls every 15 s via frappe.client.get_list
  → Count changes trigger UI refresh
```

---

## Notes

- `after_commit=True` prevents false positives if the transaction rolls back.
- The Flutter app also calls `broadcastLocal()` immediately after the action
  succeeds (before the socket event arrives) for zero-latency optimistic UI.
- If using Token auth (Api-Key/Api-Secret), socket.io is unavailable — the
  service automatically falls back to 15 s polling.
