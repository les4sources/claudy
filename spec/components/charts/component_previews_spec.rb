require "rails_helper"

# Les previews Lookbook sont du code comme le reste : si elles cassent,
# `/lookbook` casse, et personne ne s'en aperçoit avant d'y aller.
RSpec.describe "Previews Lookbook des graphes", type: :component do
  {
    Charts::StackedBarsComponentPreview => %i[with_data empty single_series],
    Charts::DonutComponentPreview => %i[with_data with_missing_accounting empty]
  }.each do |preview_class, scenarios|
    scenarios.each do |scenario|
      it "rend #{preview_class}##{scenario}" do
        expect { render_preview(scenario, from: preview_class) }.not_to raise_error
      end
    end
  end
end
