import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.close()
  }

  toggle(event) {
    event.stopPropagation()
    if (this.menuTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  closeOnOutside(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  open() {
    this.menuTarget.hidden = false
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.menuTarget.hidden = true
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "false")
  }
}
