import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = { url: String }
  static targets = ["list"]

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      animation: 150,
      onEnd: () => this.persistOrder()
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  persistOrder() {
    const ids = Array.from(this.listTarget.children)
      .map((el) => el.dataset.itemId)
      .filter(Boolean)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json"
    }
    if (token) headers["X-CSRF-Token"] = token

    fetch(this.urlValue, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ playlist_item_ids: ids })
    }).then((response) => {
      if (!response.ok) console.error("Reorder failed", response.status)
    })
  }
}
