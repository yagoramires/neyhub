import SwiftUI

/// O mesmo que @State. No SDK atual @State virou macro, e o plugin dele só vem com o Xcode;
/// como o build usa só as CommandLineTools, embrulhamos o State à mão.
@propertyWrapper
public struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>

    public init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> { state.projectedValue }
}
