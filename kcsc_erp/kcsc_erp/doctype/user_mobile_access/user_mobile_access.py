import frappe
from frappe.model.document import Document


class UserMobileAccess(Document):
    def on_update(self):
        if self.force_logout and self.has_value_changed("force_logout"):
            self._execute_force_logout()

    def _execute_force_logout(self):
        """Revoke all active sessions and notify devices via realtime event."""
        frappe.publish_realtime(
            event="force_logout",
            message={
                "user": self.user,
                "reason": "Admin initiated force logout",
            },
            user=self.user,
        )
        # Reset flag so it can be triggered again later
        frappe.db.set_value("User Mobile Access", self.name, "force_logout", 0)
        frappe.db.commit()
