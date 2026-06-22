import frappe
from frappe.model.document import Document


class UserMobileAccess(Document):
    def on_update(self):
        if self.force_logout and self.has_value_changed("force_logout"):
            self._execute_force_logout()

    def _execute_force_logout(self):
        """Push realtime event so FAC can revoke tokens and notify devices."""
        frappe.publish_realtime(
            event="force_logout",
            message={
                "user": self.user,
                "reason": "Admin initiated force logout",
            },
            user=self.user,
        )
        # Reset flag after firing so admin can trigger again later.
        # Use db_set to avoid re-triggering on_update recursively.
        self.db_set("force_logout", 0, update_modified=False)
