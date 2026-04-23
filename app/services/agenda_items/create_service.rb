module AgendaItems
  class CreateService < ServiceBase
    attr_reader :agenda_item

    def initialize(gathering:, author:)
      @agenda_item = gathering.agenda_items.build(author: author)
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }
      catch_error(context: context) { run!(params) }
    end

    def run!(params = {})
      agenda_item.attributes = agenda_item_params(params)
      agenda_item.save!
      true
    end

    private

    def agenda_item_params(params)
      params.require(:agenda_item).permit(:title, :description, :completed)
    end
  end
end
