"
I represent immutable values at compile time where all I know is the class.
"
Class {
	#name : #ASCClassValue,
	#superclass : #Object,
	#instVars : [
		'valueClass',
		'isRanged'
	],
	#category : #'ASTSmalltalk-CodeGen'
}

{ #category : #common }
ASCClassValue >> init: aClass [

	
		valueClass := aClass.
		^ self
]

{ #category : #testing }
ASCClassValue >> isMutable [

	^ false
]

{ #category : #accessing }
ASCClassValue >> isRanged [

	^ isRanged ifNil: [ isRanged := valueClass canUnderstand: #'<=']
]

{ #category : #accessing }
ASCClassValue >> kind [

	^ valueClass
]

{ #category : #serializing }
ASCClassValue >> manifest: aGenerator [
]

{ #category : #accessing }
ASCClassValue >> max [

	^ self isRanged
		  ifTrue: [ self min ]
		  ifFalse: [ nil ]
]

{ #category : #accessing }
ASCClassValue >> min [
^ nil
]

{ #category : #accessing }
ASCClassValue >> valueClass [
	^ valueClass
]