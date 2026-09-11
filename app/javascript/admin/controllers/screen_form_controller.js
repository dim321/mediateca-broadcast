import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["location", "station", "name", "inherit", "hours"]
  static values = { autoFillName: Boolean }

  connect() {
    this.filterStations()
    this.syncHoursVisibility()
  }

  locationChanged() {
    this.filterStations()
    this.fillName()
  }

  stationChanged() {
    this.fillName()
  }

  inheritChanged() {
    this.syncHoursVisibility()
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

  syncHoursVisibility() {
    if (!this.hasHoursTarget) return

    const inherit = this.hasInheritTarget && this.inheritTarget.checked
    this.hoursTarget.classList.toggle("hidden", inherit)
    this.hoursTarget.querySelectorAll("input, button").forEach((element) => {
      element.disabled = inherit
    })
  }
}
