//
//  GoodFormValidator.swift
//
//
//  Created by Maurice Kempner on 7/21/22.
//

import Foundation
import UIKit

open class GoodFormValidator: NSObject {
  public weak var delegate: GoodFormValidatorDelegate?
  private var fields = [GoodFormValidatableField]()
  private(set) var fieldConfigs = [String: GoodFormValidatableFieldConfig]()

  func registerField(_ config: GoodFormValidatableFieldConfig) {
    fieldConfigs[config.name] = config

    let input = config.field.text ?? ""
    let failedRulesTaskHandler = Task.detached {
      return try await self.failedRulesFor(config.name, with: input)
    }
    Task {
      do {
        let failedRules = try await failedRulesTaskHandler.value
        DispatchQueue.main.async {
          config.field.didInitialValidationCheck(
            isValid: failedRules.isEmpty,
            messages: failedRules.map { $0.message }
          )
          self.fieldConfigs[config.name]?.isValid = failedRules.isEmpty
        }
      } catch {
        // if error on any validation rules, just do nothing
      }
    }
  }

  func values() -> [String: String] {
    var values = [String: String]()
    fieldConfigs.values.forEach { config in
      values[config.name] = config.field.textField.text ?? ""
    }

    return values
  }

  func validateForm(_ form: GoodForm, formValues: [String: String]) async throws {
    let validateFormTask = Task {
      return try await withThrowingTaskGroup(
        of: (String, [GoodFormFieldValidationRule]).self,
        returning: [String: [GoodFormFieldValidationRule]].self,
        body: { taskGroup in
          self.fieldConfigs.values.forEach { config in
            taskGroup.addTask {
              let input = formValues[config.name] ?? ""
              let failedRules = try await self.failedRulesFor(config.name, with: input)
              return (config.name, failedRules)
            }
          }

          var results = [String: [GoodFormFieldValidationRule]]()
          for try await res in taskGroup {
            results[res.0] = res.1
          }

          return results
        }
      )
    }

    Task {
      let validationResults = try await validateFormTask.value

      if validateFormTask.isCancelled {
        // exit early if the task was cancelled
        return
      }

      for (fieldName, failedRules) in validationResults {
        if !failedRules.isEmpty {
          if let field = self.fieldConfigs[fieldName]?.field {
            DispatchQueue.main.async {
              field.didSubmitForm(
                isValid: failedRules.isEmpty,
                messages: failedRules.map { $0.message }
              )
            }
          }
        }
      }

      DispatchQueue.main.async {
        let failedRules = validationResults.values.filter { result in
          return !result.isEmpty
        }
        self.delegate?.didValidate(self, isValid: failedRules.isEmpty)
      }
    }
  }

  func failedRulesFor(
    _ name: String,
    with input: String
  ) async throws -> [GoodFormFieldValidationRule] {
    guard let config = fieldConfigs[name] else { return [] }

    let taskHandler = Task {
      return try await withThrowingTaskGroup(
        of: (GoodFormFieldValidationRule, Bool).self,
        returning: [GoodFormFieldValidationRule].self,
        body: { taskGroup in
          config.validationRules.forEach { rule in
            taskGroup.addTask {
              let isValid = try await rule.isValid(input: input)
              return (rule, isValid)
            }
          }

          var rules = [GoodFormFieldValidationRule]()
          for try await res in taskGroup {
            if !res.1 {
              rules.append(res.0)
            }
          }

          return rules
        }
      )
    }

    return try await taskHandler.value
  }
}

public protocol GoodFormValidatableField: GoodFormField {
  func didInitialValidationCheck(isValid: Bool, messages: [String])
  func didChangeValidState(isValid: Bool, messages: [String])
  func didChangeValue(isValid: Bool, messages: [String])
  func didSubmitForm(isValid: Bool, messages: [String])
}

public extension GoodFormValidatableField {
  func didInitialValidationCheck(isValid: Bool, messages: [String]) {}
  func didChangeValidState(isValid: Bool, messages: [String]) {}
  func didChangeValue(isValid: Bool, messages: [String]) {}
  func didSubmitForm(isValid: Bool, messages: [String]) {}
}

public protocol GoodFormValidatorDelegate: AnyObject {
  func didValidate(_ validator: GoodFormValidator, isValid: Bool)
}

public protocol GoodFormFieldValidationRule: AnyObject {
  var message: String { get }
  func isValid(input: String) async throws -> Bool
}

public struct GoodFormValidatableFieldConfig {
  var name: String
  var field: GoodFormValidatableField
  var validationRules: [GoodFormFieldValidationRule]
  var isValid: Bool

  public init(
    name: String,
    field: GoodFormValidatableField,
    validationRules: [GoodFormFieldValidationRule],
    isValid: Bool
  ) {
    self.name = name
    self.field = field
    self.validationRules = validationRules
    self.isValid = isValid
  }
}

public class GoodFormFullNameRule: GoodFormFieldValidationRule {
  public let message = "First and last name are required."

  public init() {}

  public func isValid(input: String) -> Bool {
    return input.split(separator: " ").count > 1
  }
}

public class GoodFormRequiredRule: GoodFormFieldValidationRule {
  public let message = "This field is required."

  public init() {}

  public func isValid(input: String) -> Bool {
    return !input.isEmpty
  }
}
