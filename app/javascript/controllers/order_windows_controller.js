import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row"]

  add(event) {
    event.preventDefault()
    if (!this.hasTemplateTarget || !this.hasListTarget) return

    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
    this.requestRecompute()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-order-windows-target='row']")
    if (!row) return

    const rows = this.listTarget.querySelectorAll("[data-order-windows-target='row']")
    if (rows.length <= 1) {
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      this.requestRecompute()
      return
    }

    row.remove()
    this.requestRecompute()
  }

  requestRecompute() {
    this.dispatch("recompute", { prefix: "order-grid" })
  }
}
