import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Human Roles Controller connected");
  }

  toggleHumanRole(event) {
    event.preventDefault();

    // Extract necessary information from the clicked link
    const humanId = this.data.get("humanId");
    const roleId = this.data.get("roleId");
    const day = this.data.get("day");

    // Check if the HumanRole exists for the current human and role
    const url = `/human_roles?human_id=${humanId}&role_id=${roleId}&date=${day}`;
    
    fetch(url)
      .then((response) => {
        if (response.ok) {
          return response.json();
        } else if (response.status === 404) {
          // If HumanRole doesn't exist, create it
          return fetch("/human_roles", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
            },
            body: JSON.stringify({ human_id: humanId, role_id: roleId, date: day }),
          }).then((createResponse) => createResponse.json());
        } else {
          throw new Error("Failed to fetch HumanRole");
        }
      })
      .then((humanRole) => {
        // Reload the Turbo Frame to update the partial
        Turbo.visit(window.location, { action: "replace" });
      })
      .catch((error) => {
        console.error("Error:", error);
      });
  }
}
