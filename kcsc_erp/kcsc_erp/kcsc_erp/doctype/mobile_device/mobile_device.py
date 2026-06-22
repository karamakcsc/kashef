import frappe
from frappe.model.document import Document


class MobileDevice(Document):
    def before_save(self):
        if self.has_value_changed("status"):
            self._notify_device_status_change()

    def _notify_device_status_change(self):
        frappe.publish_realtime(
            event="device_status_changed",
            message={
                "user": self.user,
                "device_id": self.device_id,
                "status": self.status,
            },
            user=self.user,
        )

    def block(self):
        self.status = "Blocked"
        self.save(ignore_permissions=True)

    def approve(self):
        self.status = "Active"
        self.is_trusted = 1
        self.save(ignore_permissions=True)
