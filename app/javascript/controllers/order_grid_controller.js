import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "fillFrom", "fillTo", "fillShows", "lineTemplate", "lines"]
  static values = { hours: Object }

  fillRange(event) {
    event.preventDefault()
    const from = this.fillFromTarget.value
    const to = this.fillToTarget.value
    const shows = this.fillShowsTarget.value
    if (!from || !to || shows === "") return

    this.cellTargets.forEach((cell) => {
      const date = cell.dataset.date
      if (date >= from && date <= to) cell.value = shows
    })
  }

  addLine(event) {
    event.preventDefault()
    if (!this.hasLineTemplateTarget || !this.hasLinesTarget) return

    const html = this.lineTemplateTarget.innerHTML.replaceAll("NEW_LINE", `line-${Date.now()}`)
    this.linesTarget.insertAdjacentHTML("beforeend", html)
  }

  disconnect() {
    this.cellTargets.forEach((cell) => {
      cell.dataset.filled = ""
    })
  }
}
