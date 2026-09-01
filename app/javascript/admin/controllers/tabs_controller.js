import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]
  static values = { index: Number }

  connect() {
    this.indexValueChanged()
  }

  indexValueChanged() {
    this.panelTargets.forEach((el, i) => {
      el.hidden = i !== this.indexValue
    })
  }

  select({ params: { index } }) {
    this.indexValue = index
  }
}
