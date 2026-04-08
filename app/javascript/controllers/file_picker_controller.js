import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "name"]

  connect() {
    this.defaultNameText = this.nameTarget.textContent.trim()
  }

  sync() {
    const file = this.inputTarget.files[0]
    if (file) {
      this.nameTarget.textContent = file.name
      this.nameTarget.title = file.name
    } else {
      this.nameTarget.textContent = this.defaultNameText
      this.nameTarget.title = ""
    }
  }
}
