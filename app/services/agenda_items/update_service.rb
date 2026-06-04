module AgendaItems
  class UpdateService < ServiceBase
    attr_reader :agenda_item

    def initialize(agenda_item:)
      @agenda_item = agenda_item
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }
      catch_error(context: context) { run!(params) }
    end

    def run!(params = {})
      attrs = agenda_item_params(params)
      new_files = Array(attrs.delete(:attachments)).reject(&:blank?)
      agenda_item.attributes = attrs
      agenda_item.save!
      agenda_item.attachments.attach(new_files) if new_files.any?
      true
    end

    private

    def agenda_item_params(params)
      params.require(:agenda_item).permit(:title, :description, :completed, :list, :carrier_id, attachments: [])
    end
  end
end
