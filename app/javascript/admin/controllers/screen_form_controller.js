import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["location", "station", "name"]
  static values = { autoFillName: Boolean }

  connect() {
    this.filterStations()
  }

  locationChanged() {
    this.filterStations()
    this.fillName()
  }

  stationChanged() {
    this.fillName()
  }

  filterStations() {
    if (!this.hasLocationTarget || !this.hasStationTarget) return

    const locationId = this.locationTarget.value
    Array.from(this.stationTarget.options).forEach((option) => {
      if (!option.value) {
        option.hidden = false
        return
      }

      const match = option.dataset.locationId === locationId
      option.hidden = !match
      if (!match && option.selected) option.selected = false
    })
  }

  fillName() {
    if (!this.autoFillNameValue || !this.hasNameTarget) return

    const suggested = this.suggestedName()
    const last = this.element.dataset.lastSuggestedName || ""
    if (this.nameTarget.value && this.nameTarget.value !== last) return

    this.nameTarget.value = suggested
    this.element.dataset.lastSuggestedName = suggested
  }

  suggestedName() {
    if (!this.hasStationTarget) return ""

    const option = this.stationTarget.options[this.stationTarget.selectedIndex]
    if (!option || !option.value) return ""

    return option.dataset.suggestedName || ""
  }
}
