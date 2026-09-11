import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["start", "end"]

  copyMonday(event) {
    event.preventDefault()

    const mondayStart = this.startTargets.find((input) => input.dataset.day === "mon")
    const mondayEnd = this.endTargets.find((input) => input.dataset.day === "mon")
    if (!mondayStart || !mondayEnd) return

    const startValue = mondayStart.value || ""
    const endValue = mondayEnd.value || ""

    this.startTargets.forEach((input) => {
      if (input.dataset.day !== "mon") input.value = startValue
    })
    this.endTargets.forEach((input) => {
      if (input.dataset.day !== "mon") input.value = endValue
    })
  }
}
