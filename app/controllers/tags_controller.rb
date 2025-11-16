class TagsController < ApplicationController
  def index
    @tag_totals = current_user.transactions.joins(:tags)
                               .group("tags.id", "tags.name")
                               .count
  end
end
