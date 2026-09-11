import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["locationSelect", "stationSelect"]

  connect() {
    this.filterStations()
  }

  locationChanged() {
    this.stationSelectTarget.value = ""
    this.filterStations()
  }

  filterStations() {
    const locationId = this.locationSelectTarget.value
    Array.from(this.stationSelectTarget.options).forEach((option) => {
      if (!option.value) {
        option.hidden = false
        return
      }
      const match = option.dataset.locationId === locationId
      option.hidden = !match
      if (!match && option.selected) option.selected = false
    })
  }
}
