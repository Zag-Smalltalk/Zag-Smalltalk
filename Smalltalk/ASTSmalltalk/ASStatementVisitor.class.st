Class {
	#name : #ASStatementVisitor,
	#superclass : #Object,
	#instVars : [
		'symbols',
		'stackVars',
		'aStream',
		'instructionStack',
		'closure'
	],
	#category : #'ASTSmalltalk-AST'
}

{ #category : #instantiating }
ASStatementVisitor class >> symbols: syms stackVars: stackVars closure: aClosure [

	^ self new symbols: syms stackVars: stackVars closure: aClosure
]

{ #category : #adding }
ASStatementVisitor >> addDrop [
	instructionStack add:  '&e.drop,'
]

{ #category : #accessing }
ASStatementVisitor >> findClosures: anASVar [
	self shouldBeImplemented.
]

{ #category : #accessing }
ASStatementVisitor >> instructionStack [
	^ instructionStack
]

{ #category : #constructor }
ASStatementVisitor >> symbols: syms stackVars: stackVariables closure: aClosure [

	symbols := syms.
	stackVars := stackVariables.
	closure := aClosure.
	instructionStack := OrderedCollection new
]

{ #category : #visiting }
ASStatementVisitor >> variableIndex: varName [
	^((stackVars indexOf: varName) - 1) asString
]

{ #category : #visiting }
ASStatementVisitor >> visitAssign: anASAssign [

	anASAssign expression acceptVisitor: self.
	self popValue: anASAssign variable.
]

{ #category : #visiting }
ASStatementVisitor >> visitBlockNode: anASBlock [

	| nonLocalReturnValue |
	nonLocalReturnValue := anASBlock nonLocalReturn: stackVars.
	nonLocalReturnValue
		ifNotNil: [ instructionStack add: nonLocalReturnValue ]
		ifNil: [
			instructionStack add: '&e.pushLocal, '
				,
				(self variableIndex: anASBlock selector asZigString)
				, ', //' , anASBlock selector asZigString ]
]

{ #category : #visiting }
ASStatementVisitor >> visitLiteral: anASLiteral [

	instructionStack add: ' &e.pushLiteral, Object.from(', anASLiteral literal asString, '),'.
]

{ #category : #visiting }
ASStatementVisitor >> visitNamedAS: anASLocal [

	aStream << (self variableIndex: anASLocal name)
]

{ #category : #visiting }
ASStatementVisitor >> visitReturn: anASReturn [
	anASReturn expression acceptVisitor: self.
	instructionStack add: ' &e.returnTop,'
]

{ #category : #visiting }
ASStatementVisitor >> visitSelfNode: anASSelf [

	instructionStack add:
		'&e.pushLocal, ' , (self variableIndex: #self) , ', //self'
]

{ #category : #visiting }
ASStatementVisitor >> visitSend: anASSend [

	| send |
	anASSend target acceptVisitor: self.
	anASSend args ifNotNil: [
		anASSend args do: [ :arg | arg acceptVisitor: self ] ].
	send := '&e.send' , anASSend selector numArgs asString , ', '.
	symbols
		at: anASSend selector
		ifPresent: [ :sym | send := send, sym ]
		ifAbsent: [
			self halt.
			send := send, anASSend selector ].
	instructionStack add: send , ','
]