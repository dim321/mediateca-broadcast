import { Controller } from "@hotwired/stimulus"

// Closes the mobile drawer after Turbo navigates so the overlay does not stick open.
export default class extends Controller {
  close() {
    this.element.checked = false
  }
}
