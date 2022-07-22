//
//  GoodForm.swift
//  GoodForm
//
//  Created by Maurice Kempner on 6/26/22.
//

import Foundation
import UIKit

open class GoodForm: NSObject {
  public weak var delegate: GoodFormDelegate?
  private let validator = GoodFormValidator()
  private var fields = [GoodFormField]()
  private(set) var fieldConfigs = [String: GoodFormFieldConfig]()

  public override init() {
    super.init()
    validator.delegate = self
  }

  /// Register a field in the form
  /// - Parameter config: Configuration for the field being added to the form
  public func registerField(_ config: GoodFormFieldConfig) {
    fieldConfigs[config.name] = config

    config.field.textField.addTarget(
      self,
      action: #selector(textFieldDidChange(_:)),
      for: .editingChanged
    )

    if let validatableField = config.field as? GoodFormValidatableField {
      let validatableConfig = GoodFormValidatableFieldConfig(
        name: config.name,
        field: validatableField,
        validationRules: config.validationRules,
        isValid: false
      )
      self.validator.registerField(validatableConfig)
    }
  }

  /// The current values of the form fields
  /// - Returns: Dictionary of the form field names and their current value
  public func values() -> [String: String] {
    var values = [String: String]()
    fieldConfigs.values.forEach { config in
      values[config.name] = config.field.textField.text ?? ""
    }

    return values
  }

  /// Perform validation checks (if any) on all form fields
  public func validate() {
    let formValues = values()

    Task {
      do {
        try await validator.validateForm(self, formValues: formValues)
      } catch {
        // if error on any validation rules, just do nothing
      }
    }
  }

  @objc func textFieldDidChange(_ textField: UITextField) {
    guard let config = fieldConfigFromTextField(textField) else { return }

    if let validatableField = config.field as? GoodFormValidatableField {
      let input = config.field.text ?? ""
      let failedRulesTaskHandler = Task.detached {
        return try await self.validator.failedRulesFor(config.name, with: input)
      }
      Task {
        do {
          let failedRules = try await failedRulesTaskHandler.value
          DispatchQueue.main.async {
            let isValid = failedRules.isEmpty
            let messages = failedRules.map { $0.message }
            validatableField.didChangeValue(isValid: isValid, messages: messages)
            if let validationConfig = self.validator.fieldConfigs[config.name] {
              if validationConfig.isValid != isValid {
                validatableField.didChangeValidState(isValid: isValid, messages: messages)
              }
            }
          }
        } catch {
          // if error on any validation rules, just do nothing
        }
      }
    }

    print("DBG: textFieldDidChange: \(textField.text)")
  }

  private func fieldConfigFromTextField(_ textField: UITextField) -> GoodFormFieldConfig? {
    let configs = fieldConfigs.values
    return configs.first { $0.field.textField == textField }
  }
}

extension GoodForm: GoodFormValidatorDelegate {
  public func didValidate(_ validator: GoodFormValidator, isValid: Bool) {
    print("DBG: didValidate: \(isValid)")
  }
}

public protocol GoodFormDelegate: AnyObject {
  func didValidate(_ form: GoodForm, isValid: Bool)
}

public protocol GoodFormField {
  var text: String? { get }
  var textField: UITextField { get }
}

public struct GoodFormFieldConfig {
  var name: String
  var field: GoodFormField
  var validationRules: [GoodFormFieldValidationRule]

  public init(name: String, field: GoodFormField, validationRules: [GoodFormFieldValidationRule]) {
    self.name = name
    self.field = field
    self.validationRules = validationRules
  }
}
