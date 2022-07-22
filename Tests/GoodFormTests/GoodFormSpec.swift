import Quick
import Nimble
@testable import GoodForm
import UIKit

class NameField: UITextField, GoodFormField {
  var textField: UITextField { self }
}

class GoodFormSpec: QuickSpec {
  override func spec() {
    var form: GoodForm!

    beforeEach {
      form = GoodForm()
    }

    describe("GoodForm") {
      describe("#registerField") {
        context("for non-validatable fields") {
          var field: GoodFormField!

          beforeEach {
            field = NameField()
            let fieldConfig = GoodFormFieldConfig(
              name: "name",
              field: field,
              validationRules: []
            )
            form.registerField(fieldConfig)
          }

          it("adds a field to the form") {
            expect(form.fieldConfigs).to(haveCount(1))
            expect(form.fieldConfigs["name"]?.name).to(equal("name"))
            expect(form.fieldConfigs["name"]?.field.textField).to(equal(field.textField))
            expect(form.fieldConfigs["name"]?.validationRules).to(beEmpty())
          }
        }
      }

      describe("#values") {
        var values: [String: String]!

        beforeEach {
          let field = NameField()
          field.textField.text = "Lester Tester"
          let fieldConfig = GoodFormFieldConfig(
            name: "name",
            field: field,
            validationRules: []
          )
          form.registerField(fieldConfig)
          values = form.values()
        }

        it("returns the form field values") {
          expect(values["name"]).to(equal("Lester Tester"))
        }
      }
    }
  }
}
