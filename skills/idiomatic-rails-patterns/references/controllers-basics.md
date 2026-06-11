# Controllers — Basics

Core principle, minimal ApplicationController, authorization split, and how
concerns compose into real controllers. For the catalog of resource-scoping
and filtering concerns see `controllers-resource-concerns.md`. For request-
context, security, and Turbo/view concerns see
`controllers-cross-cutting-concerns.md`.

---

## Core Principle: Thin Controllers, Rich Models

Controllers should be thin orchestrators. Business logic lives in models.

```ruby
# GOOD: Controller just orchestrates
class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    @card.close  # All logic in model

    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end

  def destroy
    @card.reopen  # All logic in model

    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end
end
```

```ruby
# BAD: Business logic in controller
class Cards::ClosuresController < ApplicationController
  def create
    @card.transaction do
      @card.create_closure!(user: Current.user)
      @card.events.create!(action: :closed, creator: Current.user)
      @card.watchers.each { |w| NotificationMailer.card_closed(w, @card).deliver_later }
    end
  end
end
```

## ApplicationController is Minimal

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include BlockSearchEngineIndexing
  include CurrentRequest, CurrentTimezone, SetPlatform
  include RequestForgeryProtection
  include TurboFlash, ViewTransitions
  include RoutingHeaders

  etag { "v1" }
  stale_when_importmap_changes
  allow_browser versions: :modern
end
```

## Authorization: Controller Checks, Model Defines

```ruby
# Controller checks permission
class CardsController < ApplicationController
  before_action :ensure_permission_to_administer_card, only: [:destroy]

  private
    def ensure_permission_to_administer_card
      head :forbidden unless Current.user.can_administer_card?(@card)
    end
end

# Model defines what permission means
class User < ApplicationRecord
  def can_administer_card?(card)
    admin? || card.creator == self
  end

  def can_administer_board?(board)
    admin? || board.creator == self
  end
end
```

---

## Composing Concerns: Real Controllers

Here's how concerns compose in practice:

```ruby
# A full-featured nested controller
class Cards::AssignmentsController < ApplicationController
  include CardScoped  # Gets @card, @board, render_card_replacement

  def new
    @assigned_to = @card.assignees.active.alphabetically.where.not(id: Current.user)
    @users = @board.users.active.alphabetically.where.not(id: @card.assignees)
    fresh_when etag: [@users, @card.assignees]  # HTTP caching!
  end

  def create
    @card.toggle_assignment @board.users.active.find(params[:assignee_id])

    respond_to do |format|
      format.turbo_stream
      format.json { head :no_content }
    end
  end
end
```

```ruby
# A timeline controller composing multiple concerns
class Events::Days::ColumnsController < ApplicationController
  include DayTimelinesScoped  # Which includes FilterScoped

  def show
    @column = @board.columns.find(params[:id])
  end
end
```

## Concern Composition Rules

1. **Concerns can include other concerns:**
   ```ruby
   module DayTimelinesScoped
     include FilterScoped  # Inherits all of FilterScoped
     # ...
   end
   ```

2. **Use `before_action` in `included` block:**
   ```ruby
   included do
     before_action :set_card
   end
   ```

3. **Provide shared private methods:**
   ```ruby
   def render_card_replacement
     # Reusable across all CardScoped controllers
   end
   ```

4. **Use `helper_method` for view access:**
   ```ruby
   included do
     helper_method :platform, :timezone_from_cookie
   end
   ```

5. **Add to `etag` for HTTP caching:**
   ```ruby
   included do
     etag { timezone_from_cookie }
   end
   ```
