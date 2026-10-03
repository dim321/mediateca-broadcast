import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    if (!this.hasButtonTarget) return

    this.template = this.buttonTarget.form.getAttribute("action")
  }

  select(event) {
    const button = this.buttonTarget
    button.form.action = this.template.replace("ORDER_ID", event.target.value)
    button.hidden = false
    button.disabled = false
    button.classList.remove("hidden")
  }
}
