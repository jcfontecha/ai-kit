import Foundation
import AIKitProviders

public struct OpenClawAgent: Sendable, Equatable {
  public var id: String
  public var name: String?
  public var identity: OpenClawAgentIdentity?

  public init(id: String, name: String?, identity: OpenClawAgentIdentity?) {
    self.id = id
    self.name = name
    self.identity = identity
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    guard let id = obj["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), id.isEmpty == false else {
      return nil
    }
    self.id = id
    self.name = obj["name"]?.stringValue
    self.identity = obj["identity"].flatMap(OpenClawAgentIdentity.init(from:))
  }
}

public struct OpenClawAgentIdentity: Sendable, Equatable {
  public var name: String?
  public var emoji: String?
  public var avatar: String?
  public var avatarUrl: String?

  public init(name: String?, emoji: String?, avatar: String?, avatarUrl: String?) {
    self.name = name
    self.emoji = emoji
    self.avatar = avatar
    self.avatarUrl = avatarUrl
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    self.name = obj["name"]?.stringValue
    self.emoji = obj["emoji"]?.stringValue
    self.avatar = obj["avatar"]?.stringValue
    self.avatarUrl = obj["avatarUrl"]?.stringValue
  }
}

public struct OpenClawAgentsList: Sendable, Equatable {
  public var defaultId: String
  public var agents: [OpenClawAgent]

  public init(defaultId: String, agents: [OpenClawAgent]) {
    self.defaultId = defaultId
    self.agents = agents
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    guard let defaultId = obj["defaultId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), defaultId.isEmpty == false else {
      return nil
    }
    let agents = obj["agents"]?.arrayValue?.compactMap(OpenClawAgent.init(from:)) ?? []
    self.defaultId = defaultId
    self.agents = agents
  }
}

public struct OpenClawAgentFile: Sendable, Equatable {
  public var content: String

  public init(content: String) {
    self.content = content
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    if let content = obj["content"]?.stringValue {
      self.content = content
      return
    }
    if let file = obj["file"]?.objectValue {
      if let content = file["content"]?.stringValue {
        self.content = content
        return
      }
      if file["missing"]?.boolValue == true {
        self.content = ""
        return
      }
    }
    return nil
  }
}

public struct OpenClawSkillRequirements: Sendable, Equatable {
  public var bins: [String]
  public var env: [String]
  public var config: [String]
  public var os: [String]

  public init(bins: [String], env: [String], config: [String], os: [String]) {
    self.bins = bins
    self.env = env
    self.config = config
    self.os = os
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    self.bins = obj["bins"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    self.env = obj["env"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    self.config = obj["config"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    self.os = obj["os"]?.arrayValue?.compactMap { $0.stringValue } ?? []
  }
}

public struct OpenClawSkill: Sendable, Equatable {
  public var name: String
  public var description: String
  public var source: String
  public var emoji: String?
  public var eligible: Bool
  public var disabled: Bool
  public var blockedByAllowlist: Bool
  public var always: Bool
  public var requirements: OpenClawSkillRequirements?

  public init(
    name: String,
    description: String,
    source: String,
    emoji: String?,
    eligible: Bool,
    disabled: Bool,
    blockedByAllowlist: Bool,
    always: Bool,
    requirements: OpenClawSkillRequirements?
  ) {
    self.name = name
    self.description = description
    self.source = source
    self.emoji = emoji
    self.eligible = eligible
    self.disabled = disabled
    self.blockedByAllowlist = blockedByAllowlist
    self.always = always
    self.requirements = requirements
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    guard let name = obj["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false else {
      return nil
    }
    guard let description = obj["description"]?.stringValue else { return nil }
    guard let source = obj["source"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), source.isEmpty == false else {
      return nil
    }

    self.name = name
    self.description = description
    self.source = source
    self.emoji = obj["emoji"]?.stringValue
    self.eligible = obj["eligible"]?.boolValue ?? false
    self.disabled = obj["disabled"]?.boolValue ?? false
    self.blockedByAllowlist = obj["blockedByAllowlist"]?.boolValue ?? false
    self.always = obj["always"]?.boolValue ?? false
    self.requirements = obj["requirements"].flatMap(OpenClawSkillRequirements.init(from:))
  }
}

public struct OpenClawSkillsStatus: Sendable, Equatable {
  public var skills: [OpenClawSkill]

  public init(skills: [OpenClawSkill]) {
    self.skills = skills
  }

  public init?(from json: JSONValue) {
    guard let obj = json.objectValue else { return nil }
    self.skills = obj["skills"]?.arrayValue?.compactMap(OpenClawSkill.init(from:)) ?? []
  }
}
