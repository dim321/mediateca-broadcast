# Owned Screens and Owner Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let client managers/admins CRUD their owned screens and manage org groups composed only of those screens (with commercial quota) in two new LK sections, without changing fleet catalog or existing screen-groups UI.

**Architecture:** Two new resource controllers (`OwnedScreensController`, `OwnedBroadcastPointGroupsController`) on existing `Screen` / `BroadcastPointGroup` models. Dedicated Pundit policies via `policy_class:` so `ScreenPolicy` (fleet read-only) stays intact. Location→station cascade via Stimulus filtering of station options (no new station API). Owner is always forced from `Current.user.organization`.

**Tech Stack:** Rails, Pundit, Hotwire (Turbo + Stimulus), Slim, daisyUI 5, RSpec request/policy specs, i18n (`mediateca.ru.yml` / `mediateca.en.yml`).

**Spec:** `docs/superpowers/specs/2026-08-12-owned-screens-and-owner-groups-design.md`

## Global Constraints

- Do **not** change behaviour of `fleet/screens` or `BroadcastPointGroupsController` / its views.
- Stations/locations are created only in Administrate; LK only selects existing ones.
- `owner_organization` is set only by the owned-screens controller — never from client params.
- Form cascade collections use full fleet `Location` / `Station` (not `policy_scope(Location)` — that scope is empty before the client owns any screens).
- Accountant denied; manager/administrator of client org allowed (`client_mutator?` / `lk_content_access?`).
- Owner groups: same actions as existing BPG (no destroy); member catalog = `owned_screens` only.
- Prefer single quotes in Ruby; Slim + daisyUI; TDD per task; commit after each green task.

## File map

| File | Responsibility |
|------|----------------|
| `app/policies/owned_screen_policy.rb` | Authorize/scope screens by `owner_organization_id` |
| `app/policies/owned_broadcast_point_group_policy.rb` | Tenant BPG mutate for owner-groups UI |
| `app/controllers/owned_screens_controller.rb` | CRUD owned screens; force owner; station/location check |
| `app/controllers/owned_broadcast_point_groups_controller.rb` | BPG CRUD + members from owned screens only |
| `app/javascript/controllers/location_station_controller.js` | Cascade: filter stations by selected location |
| `app/views/owned_screens/*` | Index/show/new/edit/_form |
| `app/views/owned_broadcast_point_groups/*` | Index/show/new/edit/_form |
| `app/views/layouts/_sidebar.html.slim` | Nav links |
| `config/routes.rb` | `owned_screens`, `owned_broadcast_point_groups` |
| `config/locales/mediateca.{ru,en}.yml` | Copy for both sections + sidebar |
| `spec/factories/screens.rb` | `:owned` trait |
| `spec/policies/owned_screen_policy_spec.rb` | Policy coverage |
| `spec/policies/owned_broadcast_point_group_policy_spec.rb` | Policy coverage |
| `spec/requests/owned_screens_spec.rb` | Request coverage |
| `spec/requests/owned_broadcast_point_groups_spec.rb` | Request coverage |

---

### Task 1: OwnedScreenPolicy + factory trait

**Files:**
- Create: `app/policies/owned_screen_policy.rb`
- Create: `spec/policies/owned_screen_policy_spec.rb`
- Modify: `spec/factories/screens.rb`

**Interfaces:**
- Produces: `OwnedScreenPolicy` with `index?`, `show?`, `create?`, `update?`, `destroy?`; `Scope#resolve` → screens where `owner_organization_id == user.organization_id` for client mutators; `none` for accountant / nil user.
- Consumes: `ApplicationPolicy#client_mutator?`, `#lk_content_access?`

- [ ] **Step 1: Write failing policy spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnedScreenPolicy do
  let(:client_org) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: client_org) }
  let(:accountant) { create(:user, :accountant, organization: client_org) }
  let(:other_manager) { create(:user, :manager, organization: create(:organization, :client)) }
  let(:owned_screen) { create(:screen, owner_organization: client_org) }
  let(:foreign_owned) { create(:screen, owner_organization: other_manager.organization) }
  let(:unowned) { create(:screen) }

  describe 'permissions' do
    it 'allows manager CRUD on own org screen' do
      policy = described_class.new(manager, owned_screen)
      expect(policy).to be_index
      expect(policy).to be_show
      expect(policy).to be_create
      expect(policy).to be_update
      expect(policy).to be_destroy
    end

    it 'denies accountant' do
      policy = described_class.new(accountant, owned_screen)
      expect(policy).not_to be_index
      expect(policy).not_to be_create
    end

    it 'denies mutate on another org owned screen' do
      policy = described_class.new(manager, foreign_owned)
      expect(policy).not_to be_show
      expect(policy).not_to be_update
      expect(policy).not_to be_destroy
    end

    it 'denies show on unowned fleet screen' do
      expect(described_class.new(manager, unowned)).not_to be_show
    end
  end

  describe 'Scope' do
    it 'returns only screens owned by the user organization' do
      owned_screen
      foreign_owned
      unowned

      resolved = described_class::Scope.new(manager, Screen.all).resolve

      expect(resolved).to contain_exactly(owned_screen)
    end

    it 'returns none for accountant' do
      owned_screen
      expect(described_class::Scope.new(accountant, Screen.all).resolve).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec — expect fail (constant missing)**

Run: `bundle exec rspec spec/policies/owned_screen_policy_spec.rb`

Expected: FAIL — `uninitialized constant OwnedScreenPolicy`

- [ ] **Step 3: Add factory trait**

In `spec/factories/screens.rb` inside `factory :screen`:

```ruby
trait :owned do
  association :owner_organization, factory: %i[organization client]
end
```

(Keep explicit `owner_organization:` in specs when tying to a specific org.)

- [ ] **Step 4: Implement policy**

```ruby
# frozen_string_literal: true

class OwnedScreenPolicy < ApplicationPolicy
  def index? = lk_content_access? && !operator_only_block?

  def show? = lk_content_access? && owned_by_user_org?

  def create? = client_mutator? && !operator_org_required_false?

  def update? = client_mutator? && owned_by_user_org?

  def destroy? = client_mutator? && owned_by_user_org?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.none unless lk_content_access?
      return scope.none if user.organization&.operator?

      scope.where(owner_organization_id: user.organization_id)
    end
  end

  private

  # Operators use Administrate; this LK surface is client-tenant only.
  def operator_only_block?
    operator?
  end

  def operator_org_required_false?
    operator?
  end

  def owned_by_user_org?
    return false unless user&.organization_id
    return false if operator?

    record.owner_organization_id == user.organization_id
  end
end
```

Simplify `create?` / `index?` to avoid noisy private helpers — final preferred form:

```ruby
# frozen_string_literal: true

class OwnedScreenPolicy < ApplicationPolicy
  def index?
    return false unless user
    return false if operator?

    lk_content_access?
  end

  def show?
    return false unless index?

    record.owner_organization_id == user.organization_id
  end

  def create?
    return false unless user
    return false if operator?

    client_mutator?
  end

  def update? = show? && client_mutator?

  def destroy? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.none if operator?
      return scope.none unless lk_content_access?

      scope.where(owner_organization_id: user.organization_id)
    end
  end
end
```

- [ ] **Step 5: Run policy spec — expect PASS**

Run: `bundle exec rspec spec/policies/owned_screen_policy_spec.rb`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/policies/owned_screen_policy.rb spec/policies/owned_screen_policy_spec.rb spec/factories/screens.rb
git commit -m "feat: add OwnedScreenPolicy for client-owned screens"
```

---

### Task 2: Owned screens routes + create/index (request specs first)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/owned_screens_controller.rb`
- Create: `spec/requests/owned_screens_spec.rb`

**Interfaces:**
- Produces: `owned_screens_path`, `new_owned_screen_path`, `owned_screen_path(screen)`; controller forces `owner_organization`.
- Consumes: `OwnedScreenPolicy`, `Station`, `Location`

- [ ] **Step 1: Write failing request specs (create + isolation)**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedScreens', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:location) { create(:location) }
  let(:station) { create(:station, location: location) }

  describe 'POST /owned_screens' do
    it 'creates a screen owned by the current organization' do
      sign_in_as(user)

      expect do
        post owned_screens_path, params: {
          location_id: location.id,
          screen: { name: 'Lobby Left', orientation: 'landscape', station_id: station.id }
        }
      end.to change(Screen, :count).by(1)

      screen = Screen.last
      expect(screen.owner_organization).to eq(organization)
      expect(screen.station).to eq(station)
      expect(response).to redirect_to(owned_screen_path(screen))
    end

    it 'ignores client-supplied owner_organization_id' do
      sign_in_as(user)
      other = create(:organization, :client)

      post owned_screens_path, params: {
        location_id: location.id,
        screen: {
          name: 'Forced Owner',
          orientation: 'portrait',
          station_id: station.id,
          owner_organization_id: other.id
        }
      }

      expect(Screen.last.owner_organization).to eq(organization)
    end

    it 'rejects station that does not belong to submitted location' do
      sign_in_as(user)
      other_station = create(:station, location: create(:location))

      expect do
        post owned_screens_path, params: {
          location_id: location.id,
          screen: { name: 'Mismatch', orientation: 'landscape', station_id: other_station.id }
        }
      end.not_to change(Screen, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /owned_screens' do
    it 'lists only screens owned by the organization' do
      sign_in_as(user)
      mine = create(:screen, owner_organization: organization, name: 'Mine')
      create(:screen, name: 'FleetOnly')
      create(:screen, owner_organization: create(:organization, :client), name: 'OtherOrg')

      get owned_screens_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mine')
      expect(response.body).not_to include('FleetOnly')
      expect(response.body).not_to include('OtherOrg')
      expect(mine).to be_persisted
    end

    it 'denies accountant' do
      accountant = create(:user, :accountant, organization: organization)
      sign_in_as(accountant)

      get owned_screens_path

      expect(response).to redirect_to(rails_health_check_path)
    end
  end
end
```

- [ ] **Step 2: Run — expect fail (routing)**

Run: `bundle exec rspec spec/requests/owned_screens_spec.rb`

Expected: FAIL — no route / uninitialized controller

- [ ] **Step 3: Add routes**

In `config/routes.rb` after `resources :locations`:

```ruby
  resources :owned_screens
```

- [ ] **Step 4: Implement controller (index/new/create + stubs for later actions)**

```ruby
# frozen_string_literal: true

class OwnedScreensController < ApplicationController
  before_action :require_user
  before_action :set_screen, only: %i[show edit update destroy]

  def index
    authorize Screen, policy_class: OwnedScreenPolicy
    @screens = policy_scope(Screen, policy_scope_class: OwnedScreenPolicy::Scope)
      .includes(station: :location)
      .order(:name)
  end

  def show
    authorize @screen, policy_class: OwnedScreenPolicy
  end

  def new
    @screen = Screen.new(orientation: :landscape)
    authorize @screen, policy_class: OwnedScreenPolicy
    load_form_collections
  end

  def create
    @screen = Screen.new(screen_params)
    @screen.owner_organization = Current.user.organization
    authorize @screen, policy_class: OwnedScreenPolicy

    if station_matches_location? && @screen.save
      redirect_to owned_screen_path(@screen), notice: t('.created')
    else
      load_form_collections
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @screen, policy_class: OwnedScreenPolicy
    load_form_collections
  end

  def update
    authorize @screen, policy_class: OwnedScreenPolicy
    @screen.assign_attributes(screen_params)
    if station_matches_location? && @screen.save
      redirect_to owned_screen_path(@screen), notice: t('.updated')
    else
      load_form_collections
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @screen, policy_class: OwnedScreenPolicy
    @screen.destroy!
    redirect_to owned_screens_path, notice: t('.destroyed')
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to owned_screen_path(@screen), alert: t('.destroy_restricted')
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t('media_assets.authentication_required')
  end

  def set_screen
    @screen = policy_scope(Screen, policy_scope_class: OwnedScreenPolicy::Scope).find(params[:id])
  end

  def screen_params
    params.require(:screen).permit(:name, :orientation, :station_id)
  end

  def load_form_collections
    @locations = Location.order(:name)
    @stations = Station.includes(:location).order(:name)
    @selected_location_id = params[:location_id].presence&.to_i
    @selected_location_id ||= @screen.station&.location_id if @screen&.station_id.present?
  end

  def station_matches_location?
    location_id = params[:location_id].presence&.to_i
    return true if location_id.blank?

    station = Station.find_by(id: @screen.station_id)
    if station.nil? || station.location_id != location_id
      @screen.errors.add(:station_id, :invalid)
      return false
    end

    true
  end
end
```

- [ ] **Step 5: Minimal views so index/create assertions on body work**

Create slim stubs (full daisyUI polish in Task 3):

`app/views/owned_screens/index.html.slim` — list `@screens` names.  
`app/views/owned_screens/new.html.slim` + `_form` — fields name/orientation/station_id + hidden/select location_id.  
`app/views/owned_screens/show.html.slim` — name.  
`app/views/owned_screens/edit.html.slim` — render form.

Minimal index:

```slim
- content_for :title, t('.title')
.mx-auto.w-full.max-w-6xl
  = render 'shared/page_header', title: t('.title')
  - @screens.each do |screen|
    p = screen.name
```

Add temporary i18n keys under `owned_screens` in both locale files (expand in Task 3):

```yaml
  owned_screens:
    index:
      title: My screens
    create:
      created: Screen created.
    update:
      updated: Screen updated.
    destroy:
      destroyed: Screen deleted.
      destroy_restricted: Screen cannot be deleted while it is used in groups or play logs.
```

Russian equivalents in `mediateca.ru.yml`.

- [ ] **Step 6: Run request spec — expect PASS**

Run: `bundle exec rspec spec/requests/owned_screens_spec.rb`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/owned_screens_controller.rb app/views/owned_screens config/locales/mediateca.ru.yml config/locales/mediateca.en.yml spec/requests/owned_screens_spec.rb
git commit -m "feat: add owned screens create and index in LK"
```

---

### Task 3: Owned screens UI (cascade Stimulus) + sidebar + update/destroy specs

**Files:**
- Create: `app/javascript/controllers/location_station_controller.js`
- Modify: `app/views/owned_screens/*` (full daisyUI)
- Modify: `app/views/layouts/_sidebar.html.slim`
- Modify: `config/locales/mediateca.ru.yml`, `mediateca.en.yml`
- Modify: `spec/requests/owned_screens_spec.rb`

**Interfaces:**
- Produces: Stimulus `location-station` controller — `locationSelect` target change filters `stationSelect` options by `data-location-id`.
- Consumes: form collections from Task 2.

- [ ] **Step 1: Extend request specs for update/destroy**

Append to `spec/requests/owned_screens_spec.rb`:

```ruby
  describe 'PATCH /owned_screens/:id' do
    it 'updates name and orientation for owned screen' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station, name: 'Old')

      patch owned_screen_path(screen), params: {
        location_id: location.id,
        screen: { name: 'New', orientation: 'portrait', station_id: station.id }
      }

      expect(response).to redirect_to(owned_screen_path(screen))
      expect(screen.reload).to have_attributes(name: 'New', orientation: 'portrait')
    end
  end

  describe 'DELETE /owned_screens/:id' do
    it 'destroys an unused owned screen' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station)

      expect do
        delete owned_screen_path(screen)
      end.to change(Screen, :count).by(-1)

      expect(response).to redirect_to(owned_screens_path)
    end

    it 'refuses destroy when screen is in a broadcast point group' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station)
      group = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect do
        delete owned_screen_path(screen)
      end.not_to change(Screen, :count)

      expect(response).to redirect_to(owned_screen_path(screen))
      expect(flash[:alert]).to be_present
    end
  end
```

- [ ] **Step 2: Run — update/destroy should already pass if controller from Task 2 is complete; fix if not**

Run: `bundle exec rspec spec/requests/owned_screens_spec.rb`

- [ ] **Step 3: Stimulus controller**

`app/javascript/controllers/location_station_controller.js`:

```javascript
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
```

(Eager-loaded via existing `controllers/index.js`.)

- [ ] **Step 4: Full `_form.html.slim`**

```slim
= form_with model: screen, url: (screen.persisted? ? owned_screen_path(screen) : owned_screens_path), class: 'space-y-4 max-w-xl', data: { controller: 'location-station' } do |f|
  - if screen.errors.any?
    ul.text-sm.text-error.list-disc.pl-5
      - screen.errors.full_messages.each do |message|
        li = message
  div
    = label_tag :location_id, t('.location'), class: 'block text-sm font-medium'
    = select_tag :location_id, \
        options_from_collection_for_select(@locations, :id, :name, @selected_location_id), \
        include_blank: t('.location_blank'), \
        class: 'select select-bordered w-full mt-1', \
        data: { location_station_target: 'locationSelect', action: 'change->location-station#locationChanged' }
  div
    = f.label :station_id, t('.station'), class: 'block text-sm font-medium'
    select.name="screen[station_id]" id="screen_station_id" class="select select-bordered w-full mt-1" data-location-station-target="stationSelect"
      option value="" = t('.station_blank')
      - @stations.each do |station|
        option value=station.id selected=(screen.station_id == station.id) data-location-id=station.location_id
          = "#{station.name} (#{station.location.name})"
  div
    = f.label :name, class: 'block text-sm font-medium'
    = f.text_field :name, class: 'input input-bordered w-full mt-1'
  div
    = f.label :orientation, class: 'block text-sm font-medium'
    = f.select :orientation, Screen.orientations.keys.map { |k| [t(".orientation.#{k}"), k] }, {}, class: 'select select-bordered w-full mt-1'
  .flex.gap-3
    = f.submit class: 'btn btn-primary btn-sm'
    = link_to t('.cancel'), owned_screens_path, class: 'btn btn-ghost btn-sm'
```

Polish index/show similarly to `fleet/screens` + `broadcast_point_groups` (page_header CTA, list-row / card, delete `button_to` with `turbo_confirm`).

- [ ] **Step 5: Sidebar links**

In `app/views/layouts/_sidebar.html.slim` inside the non-accountant branch, after fleet screens (or near groups):

```slim
      li
        = nav_link_to t("layouts.application.owned_screens"), owned_screens_path, controllers: %w[owned_screens]
      li
        = nav_link_to t("layouts.application.owned_broadcast_point_groups"), owned_broadcast_point_groups_path, controllers: %w[owned_broadcast_point_groups]
```

(Second link will 404 until Task 4 routes exist — either add both routes now as empty redirect, or add owned_screens link in this task and groups link in Task 5. **Prefer:** add only `owned_screens` nav in this task; add groups nav in Task 5.)

Locales:

```yaml
# layouts.application
owned_screens: My screens  # EN
owned_screens: Мои экраны  # RU
```

Complete `owned_screens.*` keys for form/show/index/empty/new/edit/orientations.

- [ ] **Step 6: Run specs**

Run: `bundle exec rspec spec/requests/owned_screens_spec.rb spec/policies/owned_screen_policy_spec.rb`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/location_station_controller.js app/views/owned_screens app/views/layouts/_sidebar.html.slim config/locales/mediateca.ru.yml config/locales/mediateca.en.yml spec/requests/owned_screens_spec.rb
git commit -m "feat: polish owned screens UI with location-station cascade"
```

---

### Task 4: OwnedBroadcastPointGroupPolicy

**Files:**
- Create: `app/policies/owned_broadcast_point_group_policy.rb`
- Create: `spec/policies/owned_broadcast_point_group_policy_spec.rb`

**Interfaces:**
- Produces: same action set as `BroadcastPointGroupPolicy` (`index?` `show?` `create?` `update?` `add_screens?` `remove_member?`) but **deny operators** (LK client surface) and Scope = org tenant for client mutators only.

- [ ] **Step 1: Failing policy spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnedBroadcastPointGroupPolicy do
  let(:organization) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: organization) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:other_group) { create(:broadcast_point_group, organization: create(:organization, :client)) }

  it 'allows manager to manage own org group' do
    policy = described_class.new(manager, group)
    expect(policy).to be_index
    expect(policy).to be_show
    expect(policy).to be_create
    expect(policy).to be_update
    expect(policy).to be_add_screens
    expect(policy).to be_remove_member
  end

  it 'denies accountant and foreign group show' do
    expect(described_class.new(accountant, group)).not_to be_index
    expect(described_class.new(manager, other_group)).not_to be_show
  end

  it 'scopes to organization groups' do
    group
    other_group
    resolved = described_class::Scope.new(manager, BroadcastPointGroup.all).resolve
    expect(resolved).to contain_exactly(group)
  end
end
```

- [ ] **Step 2: Run — expect fail**

Run: `bundle exec rspec spec/policies/owned_broadcast_point_group_policy_spec.rb`

- [ ] **Step 3: Implement policy**

```ruby
# frozen_string_literal: true

class OwnedBroadcastPointGroupPolicy < ApplicationPolicy
  def index?
    return false unless user
    return false if operator?

    lk_content_access?
  end

  def show?
    return false unless index?

    record.organization_id == user.organization_id
  end

  def create?
    return false unless user
    return false if operator?

    client_mutator?
  end

  def update? = show? && client_mutator?

  def add_screens? = update?

  def remove_member? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.none if operator?
      return scope.none unless lk_content_access?

      scope.where(organization_id: user.organization_id)
    end
  end
end
```

- [ ] **Step 4: Run — PASS + commit**

```bash
git add app/policies/owned_broadcast_point_group_policy.rb spec/policies/owned_broadcast_point_group_policy_spec.rb
git commit -m "feat: add OwnedBroadcastPointGroupPolicy"
```

---

### Task 5: Owned broadcast point groups controller + requests + views

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/owned_broadcast_point_groups_controller.rb`
- Create: `app/views/owned_broadcast_point_groups/{index,show,new,edit,_form}.html.slim`
- Modify: `app/views/layouts/_sidebar.html.slim`
- Modify: locales
- Create: `spec/requests/owned_broadcast_point_groups_spec.rb`

**Interfaces:**
- Produces: routes `owned_broadcast_point_groups`, member `add_screens` / `remove_member`.
- Consumes: `OwnedBroadcastPointGroupPolicy`; members from `Current.user.organization.owned_screens`.

- [ ] **Step 1: Failing request specs**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedBroadcastPointGroups', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:owned_screen) { create(:screen, owner_organization: organization) }
  let(:fleet_screen) { create(:screen) }

  describe 'POST /owned_broadcast_point_groups' do
    it 'creates a group for the organization with quota fields' do
      sign_in_as(user)
      # operating hours + membership needed only when assigning quota; create without quota first
      expect do
        post owned_broadcast_point_groups_path, params: {
          broadcast_point_group: { name: 'My owner group' }
        }
      end.to change(BroadcastPointGroup, :count).by(1)

      group = BroadcastPointGroup.last
      expect(group.organization).to eq(organization)
      expect(response).to redirect_to(owned_broadcast_point_group_path(group))
    end
  end

  describe 'POST /owned_broadcast_point_groups/:id/add_screens' do
    let!(:group) { create(:broadcast_point_group, organization: organization) }

    it 'adds an owned screen' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [owned_screen.id] }
      expect(group.reload.screens).to contain_exactly(owned_screen)
    end

    it 'rejects fleet screens not owned by the organization' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [fleet_screen.id] }
      expect(group.reload.screens).to be_empty
      expect(flash[:alert]).to be_present
    end
  end

  describe 'PATCH /owned_broadcast_point_groups/:id' do
    it 'sets commercial quota when gates are satisfied' do
      sign_in_as(user)
      location = owned_screen.station.location
      # Shape matches Location::OperatingHours — array of windows per day key.
      day_window = [ { 'start' => '09:00', 'end' => '21:00' } ]
      location.update!(
        operating_hours: {
          'mon' => day_window, 'tue' => day_window, 'wed' => day_window,
          'thu' => day_window, 'fri' => day_window, 'sat' => day_window, 'sun' => day_window
        }
      )
      group = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: owned_screen)

      patch owned_broadcast_point_group_path(group), params: {
        broadcast_point_group: {
          name: group.name,
          commercial_quota_percent: 60,
          commercial_quota_period: 'hour'
        }
      }

      expect(response).to redirect_to(owned_broadcast_point_group_path(group))
      expect(group.reload).to have_attributes(commercial_quota_percent: 60, commercial_quota_period: 'hour')
    end
  end
end
```

(Adjust if `Location#operating_hours_configured?` requires fewer days — mirror `spec/models/broadcast_point_group_spec.rb` commercial quota setup.)

- [ ] **Step 2: Run — expect fail (routes)**

Run: `bundle exec rspec spec/requests/owned_broadcast_point_groups_spec.rb`

- [ ] **Step 3: Routes**

```ruby
  resources :owned_broadcast_point_groups do
    member do
      post :add_screens
      delete :remove_member
    end
  end
```

- [ ] **Step 4: Controller**

Mirror `BroadcastPointGroupsController`, with differences:

```ruby
# frozen_string_literal: true

class OwnedBroadcastPointGroupsController < ApplicationController
  before_action :require_user
  before_action :set_group, only: %i[show edit update add_screens remove_member]

  def index
    authorize BroadcastPointGroup, policy_class: OwnedBroadcastPointGroupPolicy
    @broadcast_point_groups = policy_scope(BroadcastPointGroup, policy_scope_class: OwnedBroadcastPointGroupPolicy::Scope).order(:name)
  end

  def show
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
    @members = @broadcast_point_group.screens.includes(:station).order(:name)
    @available_screens = owned_screens_scope.where.not(id: @members.select(:id)).includes(:station).order(:name)
  end

  def new
    @broadcast_point_group = BroadcastPointGroup.new(organization: Current.user.organization)
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
  end

  def create
    @broadcast_point_group = BroadcastPointGroup.new(group_params)
    @broadcast_point_group.organization = Current.user.organization
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
    if @broadcast_point_group.save
      redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t('.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
  end

  def update
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
    if @broadcast_point_group.update(group_params)
      redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t('.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def add_screens
    authorize @broadcast_point_group, :add_screens?, policy_class: OwnedBroadcastPointGroupPolicy
    screen_ids = Array(params[:screen_ids]).compact_blank.map(&:to_i).uniq
    screens = owned_screens_scope.where(id: screen_ids)

    if screens.size != screen_ids.size
      redirect_to owned_broadcast_point_group_path(@broadcast_point_group), alert: t('.screens_not_owned')
      return
    end

    ActiveRecord::Base.transaction do
      screens.each do |screen|
        @broadcast_point_group.broadcast_point_group_memberships.create!(screen:)
      end
    end
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t('.screens_added', count: screens.size)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), alert: t('.screens_not_added')
  end

  def remove_member
    authorize @broadcast_point_group, :remove_member?, policy_class: OwnedBroadcastPointGroupPolicy
    membership = @broadcast_point_group.broadcast_point_group_memberships.find_by!(screen_id: params[:screen_id])
    membership.destroy!
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t('.member_removed')
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t('media_assets.authentication_required')
  end

  def set_group
    @broadcast_point_group = policy_scope(BroadcastPointGroup, policy_scope_class: OwnedBroadcastPointGroupPolicy::Scope).find(params[:id])
  end

  def group_params
    params.require(:broadcast_point_group).permit(
      :name,
      :commercial_quota_percent,
      :commercial_quota_period
    ).tap do |permitted|
      permitted[:commercial_quota_percent] = nil if permitted[:commercial_quota_percent].blank?
      permitted[:commercial_quota_period] = nil if permitted[:commercial_quota_period].blank?
    end
  end

  def owned_screens_scope
    Current.user.organization.owned_screens
  end
end
```

- [ ] **Step 5: Views**

Copy structure from `app/views/broadcast_point_groups/*` but:
- Paths → `owned_broadcast_point_group_*`
- No tag filter block on show
- Add-screens list from `@available_screens` only
- Form cancel → `owned_broadcast_point_groups_path`
- Reuse quota field labels (can call `t('broadcast_point_groups.form.commercial_quota_percent')` or duplicate under `owned_broadcast_point_groups.form`)

- [ ] **Step 6: i18n + sidebar link for groups**

```yaml
# layouts.application
owned_broadcast_point_groups: My groups  # EN / Мои группы RU

owned_broadcast_point_groups:
  index:
    title: My groups
    new_group: New owner group
    empty: No owner groups yet.
  # ... new/edit/form/show/create/update/add_screens/remove_member
  add_screens:
    screens_not_owned: You can only add screens you own.
```

- [ ] **Step 7: Run specs — PASS**

Run: `bundle exec rspec spec/requests/owned_broadcast_point_groups_spec.rb spec/policies/owned_broadcast_point_group_policy_spec.rb`

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/owned_broadcast_point_groups_controller.rb app/views/owned_broadcast_point_groups app/views/layouts/_sidebar.html.slim config/locales/mediateca.ru.yml config/locales/mediateca.en.yml spec/requests/owned_broadcast_point_groups_spec.rb
git commit -m "feat: add owned broadcast point groups section in LK"
```

---

### Task 6: Regression + ScreenPolicy unchanged

**Files:**
- Modify only if needed: none expected
- Test: existing specs

- [ ] **Step 1: Run regression suite**

Run:

```bash
bundle exec rspec \
  spec/policies/screen_policy_spec.rb \
  spec/requests/fleet/screens_spec.rb \
  spec/requests/broadcast_point_groups_spec.rb \
  spec/requests/owned_screens_spec.rb \
  spec/requests/owned_broadcast_point_groups_spec.rb \
  spec/policies/owned_screen_policy_spec.rb \
  spec/policies/owned_broadcast_point_group_policy_spec.rb
```

Expected: all PASS. Confirm `ScreenPolicy` still denies client `create?` and fleet catalog still lists all screens.

- [ ] **Step 2: Manual smoke (optional in agent run)**

- Sign in as client manager → sidebar «Мои экраны» / «Мои группы»
- Create screen: pick location → stations filter → save → appears only in Мои экраны
- Create group → add owned screen → set quota (with location hours) → success
- Try add non-owned screen id → alert
- Existing «Группы экранов» still adds fleet screens

- [ ] **Step 3: Commit only if fixes were needed; otherwise done**

```bash
# if any fix commits:
git commit -m "test: regress fleet screens and legacy groups after owned sections"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Мои экраны CRUD + forced owner | 1–3 |
| Location → station cascade | 3 |
| Station must match location_id | 2 |
| Destroy restrict flash | 3 |
| Мои группы without touching legacy BPG UI | 5 |
| Members only owned_screens | 5 |
| Commercial quota via existing model gates | 5 |
| Accountant denied | 1, 2, 4 |
| fleet/screens + broadcast_point_groups unchanged | 6 |
| No tags / no station create / no new tables | — out of scope, verified by file map |

## Placeholder / consistency review

- Operating hours in Task 5 use the array-of-windows shape from `broadcast_point_group_spec`.
- Policy method names (`add_screens?`, `remove_member?`) match controller `authorize` calls.
- Route helpers: `owned_screen_path`, `owned_broadcast_point_group_path`, `add_screens_owned_broadcast_point_group_path`.
