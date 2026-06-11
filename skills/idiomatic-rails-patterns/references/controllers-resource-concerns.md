# Controllers — Resource & Filtering Concerns

Resource-scoping concerns (CardScoped, BoardScoped, ColumnScoped) and
filtering concerns (FilterScoped). These set up `@record` ivars and shared
private helpers for any controller nested under that resource.

For basics (thin-controllers principle, ApplicationController, authorization)
see `controllers-basics.md`. For request-context, security, and Turbo/view
concerns see `controllers-cross-cutting-concerns.md`.

---

## Resource Scoping Concerns

### CardScoped — For Card Sub-resources

```ruby
# app/controllers/concerns/card_scoped.rb
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card, :set_board
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find_by!(number: params[:card_id])
    end

    def set_board
      @board = @card.board
    end

    def render_card_replacement
      render turbo_stream: turbo_stream.replace(
        [@card, :card_container],
        partial: "cards/container",
        method: :morph,
        locals: { card: @card.reload }
      )
    end
end
```

**Usage Pattern:**

```ruby
# Any controller nested under cards uses this
class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    @card.close
    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end
end

class Cards::WatchesController < ApplicationController
  include CardScoped

  def create
    @card.watch_by Current.user
    # ...
  end
end

class Cards::PinsController < ApplicationController
  include CardScoped

  def create
    @pin = @card.pin_by Current.user
    # ...
  end
end
```

**Key insight:** The concern provides `render_card_replacement` — a shared way to update the card UI.

### BoardScoped — For Board Sub-resources

```ruby
# app/controllers/concerns/board_scoped.rb
module BoardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_board
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def ensure_permission_to_admin_board
      unless Current.user.can_administer_board?(@board)
        head :forbidden
      end
    end
end
```

**Usage:**

```ruby
class Boards::ColumnsController < ApplicationController
  include BoardScoped

  def create
    @column = @board.columns.create!(column_params)
  end
end

class Boards::PublicationsController < ApplicationController
  include BoardScoped
  before_action :ensure_permission_to_admin_board

  def create
    @board.publish
  end
end
```

### ColumnScoped — For Column Sub-resources

```ruby
# app/controllers/concerns/column_scoped.rb
module ColumnScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_column
  end

  private
    def set_column
      @column = Current.user.accessible_columns.find(params[:column_id])
    end
end
```

---

## Filtering & Pagination Concerns

### FilterScoped — Complex Filtering

```ruby
# app/controllers/concerns/filter_scoped.rb
module FilterScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_filter
    before_action :set_user_filtering
  end

  private
    def set_filter
      if params[:filter_id].present?
        @filter = Current.user.filters.find(params[:filter_id])
      else
        @filter = Current.user.filters.from_params(filter_params)
      end
    end

    def filter_params
      params.reverse_merge(**Filter.default_values)
            .permit(*Filter::PERMITTED_PARAMS)
    end

    def set_user_filtering
      @user_filtering = User::Filtering.new(Current.user, @filter, expanded: expanded_param)
    end
end
```

**The Filter model does the heavy lifting:**

```ruby
class Filter < ApplicationRecord
  def cards
    result = creator.accessible_cards.preloaded.published
    result = result.indexed_by(indexed_by)
    result = result.sorted_by(sorted_by)
    result = result.where(board: boards.ids) if boards.present?
    result = result.tagged_with(tags.ids) if tags.present?
    result = result.assigned_to(assignees.ids) if assignees.present?
    # ... more filtering
    result.distinct
  end
end
```

**Pattern:** Filters are persisted! Users can save and name their filters.
