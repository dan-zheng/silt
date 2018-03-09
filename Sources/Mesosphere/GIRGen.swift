/// GIRGen.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle
import Seismography

public final class GIRGenModule {
  fileprivate var M: GIRModule
  let module: Module
  let environment: Environment
  let signature: Signature
  let tc: TypeChecker<CheckPhaseState>

  struct DelayedContinuation {
    let force: () -> Continuation
  }

  var emittedFunctions: [DeclRef: Continuation] = [:]

  typealias DelayedEmitter = (Continuation) -> ()

  var delayedFunctions: [DeclRef: (Continuation) -> ()] = [:]

  public init(_ root: TopLevelModule) {
    self.module = root.rootModule
    self.M = GIRModule(name: root.name.string)
    self.environment = root.environment
    self.signature = root.signature
    self.tc = root.tc
  }

  public func emitTopLevelModule() -> GIRModule {
    var visitedDecls = Set<QualifiedName>()
    for declKey in self.module.inside {
      guard visitedDecls.insert(declKey).inserted else { continue }

      guard let def = self.signature.lookupDefinition(declKey) else {
        fatalError()
      }
      self.emitContextualDefinition(declKey.string, def)
    }
    return self.M
  }

  func getEmittedFunction(_ ref: DeclRef) -> Continuation? {
    return self.emittedFunctions[ref]
  }
}

extension GIRGenModule {
  func emitContextualDefinition(_ name: String, _ def: ContextualDefinition) {
    precondition(def.telescope.isEmpty, "Cannot gen generics yet")

    switch def.inside {
    case .module(_):
      fatalError()
    case let .constant(ty, constant):
      self.emitContextualConstant(name, constant, ty, def.telescope)
    case .dataConstructor(_, _, _):
      fatalError()
    case .projection(_, _, _):
      fatalError()
    }
  }

  func emitContextualConstant(_ name: String, _ c: Definition.Constant, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch c {
    case let .function(inst):
      self.emitFunction(name, inst, ty, tel)
    case .postulate:
      fatalError()
    case .data(_):
      break
    case .record(_, _, _):
      fatalError()
    }
  }

  func emitFunction(_ name: String, _ inst: Instantiability, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch inst {
    case .open:
      return // Nothing to do for opaque functions.
    case let .invertible(body):
      let clauses = body.ignoreInvertibility
      let constant = DeclRef(name, .function)
      let f = Continuation(name: constant.name, type: BottomType.shared)
      self.M.addContinuation(f)
      GIRGenFunction(self, f, ty, tel).emitFunction(clauses)
    }
  }

  func emitFunctionBody(_ constant: DeclRef, _ emitter: @escaping DelayedEmitter) {
    guard let f = self.getEmittedFunction(constant) else {
      self.delayedFunctions[constant] = emitter
      return
    }
    return emitter(f)
  }
}

final class GIRGenFunction {
  var f: Continuation
  let B: IRBuilder
  let params: [(Name, Type<TT>)]
  let returnTy: Type<TT>
  let telescope: Telescope<TT>

  init(_ GGM: GIRGenModule, _ f: Continuation, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    self.f = f
    self.B = IRBuilder(module: GGM.M)
    self.telescope = tel
    let (ps, result) = GGM.tc.unrollPi(ty)
    self.params = ps
    self.returnTy = result
  }

  func emitFunction(_ clauses: [Clause]) {
    let returnCont = self.buildParameterList()
    self.emitPatternMatrix(clauses, returnCont)
  }

  func buildParameterList() -> Value {
    for (_, paramTy) in self.params {
      self.f.appendParameter(type: BottomType.shared, ownership: .owned)
    }
    return self.f.appendParameter(type: BottomType.shared, ownership: .owned)
  }

  func emitPatternMatrix(_ matrix: [Clause], _ returnCont: Value) {
    guard let firstRow = matrix.first else {
      _ = self.B.createUnreachable(self.f)
      return
    }

    guard !firstRow.patterns.isEmpty else {
      guard let body = firstRow.body else {
        _ = self.B.createUnreachable(self.f)
        return
      }
      let RV = self.emitRValue(body)
      _ = self.B.createApply(self.f, returnCont, [RV])
      return
    }

    guard let body = firstRow.body else {
      _ = self.B.createUnreachable(self.f)
      return
    }

    let RV = self.emitRValue(body)
    _ = self.B.createApply(self.f, returnCont, [RV])
  }

  func emitRValue(_ body: Term<TT>) -> Value {
    fatalError()
  }
}
