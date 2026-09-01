import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import OrderGridController from "controllers/order_grid_controller"

const application = Application.start()
application.debug = false
window.Stimulus = application

eagerLoadControllersFrom("admin/controllers", application)
application.register("order-grid", OrderGridController)
