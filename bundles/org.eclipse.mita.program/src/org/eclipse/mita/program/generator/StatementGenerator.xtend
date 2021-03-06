/********************************************************************************
 * Copyright (c) 2017, 2018 Bosch Connected Devices and Solutions GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 *
 * Contributors:
 *    Bosch Connected Devices and Solutions GmbH - initial contribution
 *
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

package org.eclipse.mita.program.generator

import com.google.inject.Inject
import java.util.LinkedList
import java.util.List
import java.util.Optional
import java.util.function.Function
import org.eclipse.core.runtime.CoreException
import org.eclipse.core.runtime.IStatus
import org.eclipse.core.runtime.Status
import org.eclipse.emf.ecore.EObject
import org.eclipse.mita.base.expressions.AbstractStatement
import org.eclipse.mita.base.expressions.Argument
import org.eclipse.mita.base.expressions.ArgumentExpression
import org.eclipse.mita.base.expressions.ArrayAccessExpression
import org.eclipse.mita.base.expressions.AssignmentExpression
import org.eclipse.mita.base.expressions.AssignmentOperator
import org.eclipse.mita.base.expressions.BinaryExpression
import org.eclipse.mita.base.expressions.BoolLiteral
import org.eclipse.mita.base.expressions.ConditionalExpression
import org.eclipse.mita.base.expressions.DoubleLiteral
import org.eclipse.mita.base.expressions.ElementReferenceExpression
import org.eclipse.mita.base.expressions.ExpressionStatement
import org.eclipse.mita.base.expressions.FeatureCall
import org.eclipse.mita.base.expressions.FloatLiteral
import org.eclipse.mita.base.expressions.HexLiteral
import org.eclipse.mita.base.expressions.IntLiteral
import org.eclipse.mita.base.expressions.Literal
import org.eclipse.mita.base.expressions.NullLiteral
import org.eclipse.mita.base.expressions.ParenthesizedExpression
import org.eclipse.mita.base.expressions.PostFixUnaryExpression
import org.eclipse.mita.base.expressions.PrimitiveValueExpression
import org.eclipse.mita.base.expressions.StringLiteral
import org.eclipse.mita.base.expressions.TypeCastExpression
import org.eclipse.mita.base.expressions.UnaryExpression
import org.eclipse.mita.base.expressions.ValueRange
import org.eclipse.mita.base.expressions.util.ExpressionUtils
import org.eclipse.mita.base.types.AnonymousProductType
import org.eclipse.mita.base.types.CoercionExpression
import org.eclipse.mita.base.types.EnumerationType
import org.eclipse.mita.base.types.Expression
import org.eclipse.mita.base.types.GeneratedFunctionDefinition
import org.eclipse.mita.base.types.InterpolatedStringLiteral
import org.eclipse.mita.base.types.NamedProductType
import org.eclipse.mita.base.types.Operation
import org.eclipse.mita.base.types.Parameter
import org.eclipse.mita.base.types.Property
import org.eclipse.mita.base.types.Singleton
import org.eclipse.mita.base.types.StructureType
import org.eclipse.mita.base.types.SumAlternative
import org.eclipse.mita.base.types.SumSubTypeConstructor
import org.eclipse.mita.base.types.SumType
import org.eclipse.mita.base.types.TypeAccessor
import org.eclipse.mita.base.types.TypeConstructor
import org.eclipse.mita.base.types.TypeSpecifier
import org.eclipse.mita.base.types.TypeUtils
import org.eclipse.mita.base.types.VirtualFunction
import org.eclipse.mita.base.typesystem.BaseConstraintFactory
import org.eclipse.mita.base.typesystem.types.AbstractType
import org.eclipse.mita.base.typesystem.types.AtomicType
import org.eclipse.mita.base.typesystem.types.FunctionType
import org.eclipse.mita.base.typesystem.types.NumericType
import org.eclipse.mita.base.typesystem.types.ProdType
import org.eclipse.mita.base.typesystem.types.TypeConstructorType
import org.eclipse.mita.base.typesystem.types.TypeScheme
import org.eclipse.mita.base.typesystem.types.TypeVariable
import org.eclipse.mita.base.util.BaseUtils
import org.eclipse.mita.platform.Modality
import org.eclipse.mita.program.ArrayLiteral
import org.eclipse.mita.program.ArrayRuntimeCheckStatement
import org.eclipse.mita.program.ConfigurationItemValue
import org.eclipse.mita.program.DereferenceExpression
import org.eclipse.mita.program.DoWhileStatement
import org.eclipse.mita.program.ExceptionBaseVariableDeclaration
import org.eclipse.mita.program.ForEachStatement
import org.eclipse.mita.program.ForStatement
import org.eclipse.mita.program.FunctionDefinition
import org.eclipse.mita.program.IfStatement
import org.eclipse.mita.program.IsAssignmentCase
import org.eclipse.mita.program.IsDeconstructionCase
import org.eclipse.mita.program.IsDeconstructor
import org.eclipse.mita.program.IsOtherCase
import org.eclipse.mita.program.IsTypeMatchCase
import org.eclipse.mita.program.LoopBreakerStatement
import org.eclipse.mita.program.ModalityAccess
import org.eclipse.mita.program.ModalityAccessPreparation
import org.eclipse.mita.program.NativeFunctionDefinition
import org.eclipse.mita.program.NoopStatement
import org.eclipse.mita.program.Program
import org.eclipse.mita.program.ProgramBlock
import org.eclipse.mita.program.ReferenceExpression
import org.eclipse.mita.program.ReturnParameterDeclaration
import org.eclipse.mita.program.ReturnStatement
import org.eclipse.mita.program.ReturnValueExpression
import org.eclipse.mita.program.SignalInstance
import org.eclipse.mita.program.SourceCodeComment
import org.eclipse.mita.program.SystemResourceSetup
import org.eclipse.mita.program.ThrowExceptionStatement
import org.eclipse.mita.program.TryStatement
import org.eclipse.mita.program.VariableDeclaration
import org.eclipse.mita.program.WhereIsStatement
import org.eclipse.mita.program.WhileStatement
import org.eclipse.mita.program.generator.internal.GeneratorRegistry
import org.eclipse.mita.program.model.ModelUtils
import org.eclipse.xtend2.lib.StringConcatenationClient
import org.eclipse.xtext.EcoreUtil2
import org.eclipse.xtext.generator.trace.node.CompositeGeneratorNode
import org.eclipse.xtext.generator.trace.node.IGeneratorNode
import org.eclipse.xtext.generator.trace.node.Traced

import static org.eclipse.mita.base.types.TypeUtils.*
import static org.eclipse.mita.program.model.ModelUtils.*

import static extension org.eclipse.emf.common.util.ECollections.asEList
import static extension org.eclipse.mita.base.types.TypeUtils.getConstraintSystem
import static extension org.eclipse.mita.base.types.TypeUtils.ignoreCoercions
import static extension org.eclipse.mita.base.util.BaseUtils.castOrNull
import org.eclipse.mita.program.ReturnParameterReference

class StatementGenerator {

	@Inject extension ProgramDslTraceExtensions
	
	@Inject
	protected extension GeneratorUtils

	@Inject
	protected TypeGenerator typeGenerator

	@Inject(optional=true)
	protected IPlatformExceptionGenerator exceptionGenerator

	@Inject
	protected CodeFragmentProvider codeFragmentProvider

	@Inject
	protected GeneratorRegistry registry
	
	dispatch def IGeneratorNode code(Void stmt) {
		return codeFragmentProvider.create('''CODE CALLED ON NULL''');
	}

	private def cf(StringConcatenationClient scc) {
		codeFragmentProvider.create(scc);
	}
	private def cf(IGeneratorNode node) {
		codeFragmentProvider.create('''«node»''');
	}

	@Traced dispatch def IGeneratorNode code(Argument stmt) {
		'''«stmt.value.code»'''
	}

	@Traced dispatch def IGeneratorNode code(StringLiteral stmt) {
		val printContext = stmt
			?.eContainer?.castOrNull(PrimitiveValueExpression)
			?.eContainer?.castOrNull(Argument)
			?.eContainer?.castOrNull(ElementReferenceExpression)
			?.reference?.castOrNull(GeneratedFunctionDefinition)
			?.name
		val setupContext = EcoreUtil2.getContainerOfType(stmt, SystemResourceSetup) as EObject ?:
						   EcoreUtil2.getContainerOfType(stmt, ConfigurationItemValue)
		// don't create complicated stuff for:
		// - print (nicer code)
		// - setup (easier usage in platform components)
		if(printContext == "print" || printContext == "println" || setupContext !== null) {
			return '''"«stmt.value»"'''
		}

		return '''
			«IF !stmt.isTopLevel»(«typeGenerator.code(stmt, BaseUtils.getType(stmt))») «ENDIF»{
				.data = "«stmt.value»",
				.capacity = «stmt.value.length»,
				.length = «stmt.value.length»,
			}
		'''
		
	}

	@Traced dispatch def code(NullLiteral stmt) {
		'''NULL'''
	}

	@Traced dispatch def IGeneratorNode code(IntLiteral stmt) {
		'''«stmt.value»'''
	}

	@Traced dispatch def IGeneratorNode code(HexLiteral stmt) {
		'''0x«Long.toHexString(stmt.value)»'''
	}

	@Traced dispatch def IGeneratorNode code(FloatLiteral stmt) {
		'''«stmt.value»f'''
	}

	@Traced dispatch def IGeneratorNode code(DoubleLiteral stmt) {
		'''«stmt.value»'''
	}

	@Traced dispatch def IGeneratorNode code(BoolLiteral stmt) {
		val result = codeFragmentProvider
			.create('''«IF stmt.value»true«ELSE»false«ENDIF»''')
			.addHeader('stdbool.h', true);
		return '''«result»''';
	}
		
	@Traced dispatch def IGeneratorNode code(ArrayLiteral stmt) {
		'''«IF !stmt.isTopLevel»(«typeGenerator.code(stmt, BaseUtils.getType(stmt))») «ENDIF»{
			.data = («typeGenerator.code(stmt, (BaseUtils.getType(stmt) as TypeConstructorType).typeArguments.get(1))»[«stmt.values.length»]) {«FOR value: stmt.values SEPARATOR(', ')»«value.code»«ENDFOR»},
			.capacity = «stmt.values.length»,
			.length = «stmt.values.length»,
		}'''
	}
	
	@Traced dispatch def IGeneratorNode code(Literal stmt) {
		'''ERROR: unsupported literal: «stmt»'''
	}

	@Traced dispatch def IGeneratorNode code(UnaryExpression stmt) {
		'''«stmt.operator.literal»«stmt.operand.code»'''
	}
	
	@Traced dispatch def IGeneratorNode code(PostFixUnaryExpression stmt) {
		'''«stmt.operand.code.noTerminator»«stmt.operator.literal»«IF stmt.eContainer instanceof ExpressionStatement»;«ENDIF»'''
	}

	@Traced dispatch def IGeneratorNode code(TypeCastExpression stmt) {
		/* TODO: replace this hack with a typecast expression that supports TypeSpecifier
		 * see https://github.com/Yakindu/statecharts/issues/1779
		 */
		val type = BaseUtils.getType(stmt)

		'''(«typeGenerator.code(stmt, type)») («stmt.operand.code.noTerminator»)'''
	}

	@Traced dispatch def IGeneratorNode code(PrimitiveValueExpression stmt) {
		'''«stmt.value.code»'''
	}

	@Traced dispatch def IGeneratorNode code(ParenthesizedExpression stmt) {
		'''(«stmt.expression.code.noTerminator»);'''
	}

	@Traced dispatch def IGeneratorNode code(BinaryExpression stmt) {
		// TODO: handle strings and reference types
		'''«stmt.leftOperand.code.noTerminator» «stmt.operator.literal» «stmt.rightOperand.code.noTerminator»'''
	}

	dispatch def IGeneratorNode code(ModalityAccess stmt) {
		/*
		 * At this point we should have generated code preparing this access.
		 * The generator will expect that, but so far we don't have an explicit
		 * state sharing between sensor access preparation and modality access.
		 */
		val sensor = stmt.preparation.systemResource;
		val generator = registry.getGenerator(sensor);
		generator.generateModalityAccessFor(stmt)
			.addHeader(stmt.preparation.systemResource.fileBasename + '.h', false);
	}

	dispatch def IGeneratorNode code(ModalityAccessPreparation stmt) {
		val sensor = stmt.systemResource;
		val generator = registry.getGenerator(sensor);
		
		// here our generator concept fails us. We are unable to provide all the state to the generator!
		generator.prepare(null, sensor, null, null, null);
		
		generator.generateAccessPreparationFor(stmt).addHeader(stmt.systemResource.fileBasename + '.h', false);
	}

	@Traced dispatch def IGeneratorNode code(ArrayAccessExpression stmt) {
		val arraySelector = stmt.arraySelector;
		if(arraySelector instanceof ValueRange) {
			// value ranges should be handled by generator. Return reference to element.
			return '''«stmt.owner.code»''';
		}
		else {
			return '''«stmt.owner.code».data[«stmt.arraySelector.code.noTerminator»]''';
		}
	}
	
	def CodeFragment generateBulkAllocation(EObject context, CodeFragment cVariablePrefix, CodeWithContext left, CodeFragment count, boolean isTopLevel) {
		if(isGeneratedType(context, left.type)) {
			val generator = registry.getGenerator(context.eResource, left.type).castOrNull(AbstractTypeGenerator);
			
			return generator.generateBulkAllocation(context, cVariablePrefix, left, count, isTopLevel);
		}
		return cf('''''')
	}
	def CodeFragment generateBulkAssignment(EObject context, CodeFragment cVariablePrefix, CodeWithContext left, CodeFragment count) {
		if(isGeneratedType(context, left.type)) {
			val generator = registry.getGenerator(context.eResource, left.type).castOrNull(AbstractTypeGenerator);
			
			return generator.generateBulkAssignment(context, cVariablePrefix, left, count);
		}
		return cf('''''')
	}
	def CodeFragment generateBulkCopyStatements(EObject context, CodeFragment i, CodeWithContext left, CodeWithContext right, CodeFragment count) {
		if(isGeneratedType(context, left.type)) {
			val generator = registry.getGenerator(context.eResource, left.type).castOrNull(AbstractTypeGenerator);
			
			return generator.generateBulkCopyStatements(context, i, left, right, count);
		}
		val typeSize = cf('''sizeof(«typeGenerator.code(context, left.type)»)''')
		return cf('''
			/* «left.code» = «right.code» */
			memcpy(«left.code», «right.code», «typeSize» * «count»);
		''')
	}
	
	@Traced dispatch def IGeneratorNode code(ArrayRuntimeCheckStatement stmt) {
		val accessStatement = stmt.access;
		val owner = accessStatement.owner;
		val variableName = owner.code
		
		val checks = new LinkedList<CodeFragment>();
		val arraySelector = accessStatement.arraySelector.ignoreCoercions; 
		val arrayLength = codeFragmentProvider.create('''«variableName».length''');
		if(arraySelector instanceof ValueRange) {			
			if(arraySelector.lowerBound !== null) {
				checks += cf('''«arraySelector.lowerBound.code.noTerminator» < 0''');
			}
			if(arraySelector.upperBound !== null) {
				checks += cf('''«arraySelector.upperBound.code.noTerminator» >= «arrayLength»''');
			}
			if(arraySelector.lowerBound !== null && arraySelector.upperBound !== null) {				
				checks += cf('''«arraySelector.lowerBound.code.noTerminator» > «arraySelector.upperBound.code.noTerminator»''');
			}
		} else {
			checks += cf('''«arrayLength» <= «arraySelector.code.noTerminator»''');
		}
		
		return '''
		«IF !checks.empty»
		if(«FOR check: checks SEPARATOR(" || ")»«check»«ENDFOR») {
			«generateExceptionHandler(stmt, "EXCEPTION_INVALIDRANGEEXCEPTION")»
		}
		«ENDIF»
		''';
	}
	
	@Traced dispatch def IGeneratorNode code(CoercionExpression expr) {
		val coercedType = BaseUtils.getType(expr);
		val expressionType = BaseUtils.getType(expr.value);
		if(coercedType == expressionType) {
			// inserting this coercion seems to have fixed some subtypes to be equal.
			// since they are both equal just return expr.value.code.
			return '''«expr.value.code»''';
		}
		if(coercedType instanceof org.eclipse.mita.base.typesystem.types.SumType) {
			if(!(expressionType instanceof org.eclipse.mita.base.typesystem.types.SumType)) {
				val altAccessor = expressionType.getNameInStruct(expr);
				val needCast = EcoreUtil2.getContainerOfType(expr, ProgramBlock) !== null;
				val expressionTypeIsSingleton = expr.eResource.constraintSystem.getUserData(expressionType, BaseConstraintFactory.ECLASS_KEY) == "Singleton"
				return '''
				(«IF needCast»(«coercedType.getStructType(expr)») «ENDIF»{
					.tag = «expressionType.getEnumName(expr)»«IF !(expressionTypeIsSingleton)», ««« there is no other field for singletons

					.data.«altAccessor» = «expr.value.code»
				«ENDIF»
				
				})

				'''
			}
		}
		if(TypeUtils.isGeneratedType(expr, coercedType)) {
			val generator = registry.getGenerator(expr.eResource, coercedType) as AbstractTypeGenerator;
			return '''«generator.generateCoercion(expr, expressionType, coercedType)»'''; 
		}
		if(coercedType instanceof TypeConstructorType) {
			// can't really cast these. This should only happen for literals.
			return '''«expr.value.code»''';
		}
		return '''((«(expr.typeSpecifier as AbstractType).getCtype(expr)») «expr.value.code»)'''
	}
	
	@Traced dispatch def IGeneratorNode code(FeatureCall stmt) {
		val arguments = ExpressionUtils.getArgumentsOfElementReferenceExpression(stmt);
		if (stmt.operationCall) {
			val feature = stmt.reference;
			if(feature instanceof SumAlternative) {

			} else {
				/* The pogram transformation pipeline rewrites extension methods to regular element reference expressions.
				 * Thus, we should never get here.
				 */
				return '''«_code(stmt as ElementReferenceExpression)»'''
			}
		} else if (stmt.isArrayAccess) {
			'''«arguments.head.value.code.noTerminator»[«stmt.arraySelector.head.code.noTerminator»];'''
		} else if (stmt.reference instanceof Modality) {
			throw new CoreException(new Status(IStatus.ERROR, null, 'Sensor access should not be a feature call'));
		} else if (stmt.reference instanceof SignalInstance) {
			'''/* Signal instance access should have been rewritten by the compiler. */'''
		} else if (stmt.reference instanceof VariableDeclaration) {
			/* This slightly obscure case is for signal read access where the transformation pipeline
			 * replaces the original feature with the SignalInstanceReadAccess variable declaration.
			 */
			val declaration = stmt.reference as VariableDeclaration;
			'''«declaration.name»'''
		} else if (stmt.reference instanceof Property) {
			val _feature = stmt.reference as Property
			'''«stmt.reference.code.noTerminator».«_feature.name»'''
		} else if (stmt.reference instanceof Parameter) {
			val _feature = stmt.reference as Parameter
			'''«arguments.head.value.code.noTerminator».«_feature.name»'''
		}
	}

	@Traced dispatch def IGeneratorNode generateVirtualFunctionCall(EObject callSite, TypeConstructor cons, Iterable<Argument> arguments) {
		val needCast = EcoreUtil2.getContainerOfType(callSite, ProgramBlock) !== null;
		val structuralType = cons.eContainer;
		'''
		«IF needCast»(«structuralType.structType») «ENDIF»{
			«FOR i_arg : arguments.indexed SEPARATOR (',\n')»
			.«IF i_arg.value.parameter !== null»«i_arg.value.parameter.name»«ELSE»«cons.parameters.get(i_arg.key).name»«ENDIF» = «i_arg.value.value.code»
			«ENDFOR»
		}'''
	}
	@Traced dispatch def IGeneratorNode generateVirtualFunctionCall(EObject callSite, TypeAccessor accessor, Iterable<Argument> arguments) {
		'''«arguments.head.code».«accessor.name»'''
	}
	@Traced dispatch def IGeneratorNode generateVirtualFunctionCall(EObject callSite, VirtualFunction fun, Iterable<Argument> arguments) {
		'''NOT IMPLEMENTED: «fun.eClass»''';
	}

	@Traced dispatch def IGeneratorNode generateVirtualFunctionCall(EObject callSite, SumSubTypeConstructor cons, Iterable<Argument> arguments) {
		val eConstructingType = cons.eContainer;
		val constructingType = BaseUtils.getType(eConstructingType);
		// the result destination of this expression has type of either the constructor or its parent sum type.
		// if this expression is part of a return statement then the sum type would be inferred at the function definition.
		val EObject expressionDestination = if(EcoreUtil2.getContainerOfType(callSite, ReturnValueExpression) !== null) {
			EcoreUtil2.getContainerOfType(callSite, Operation)?.typeSpecifier;
		} 
		else {
			// things like assignments etc.
			EcoreUtil2.getContainerOfType(callSite, AbstractStatement);	
		}
		val constructedType = BaseUtils.getType(expressionDestination);
		val realConstructedType = getRealType(callSite, constructingType);
		if(realConstructedType !== constructingType) {
			// we embed some other type. 
			// since the user needs to construct this explicitly we can just call code on the argument which constructs the real type.
			return '''«arguments.tail.head.code»''';
		}
		if(eConstructingType instanceof SumAlternative) {
			val altAccessor = constructingType.getNameInStruct(callSite);
			val eSumType = eConstructingType.eContainer;
			val sumType = BaseUtils.getType(eSumType);
			val dataType = getRealType(callSite, constructingType).getCtype(callSite)
			// global initialization must not cast, local reassignment must cast, local initialization may cast. Therefore we cast when we are local.
			val needCast = EcoreUtil2.getContainerOfType(callSite, ProgramBlock) !== null
			
			val hasAccessors = hasNamedMembers(callSite, realConstructedType);
			
			val returnTypeIsSumType = constructedType instanceof org.eclipse.mita.base.typesystem.types.SumType;
			
			val constructingTypeIsSingleton = TypeUtils
				 .getConstraintSystem(callSite.eResource)
				?.getUserData(constructingType, BaseConstraintFactory.ECLASS_KEY) == "Singleton";
			
			val constructedStruct = cf('''
			«IF returnTypeIsSumType || needCast»(«dataType»)«ENDIF» {
				«FOR i_arg: arguments.tail.indexed»
				«IF hasAccessors»«accessor(callSite, eConstructingType, i_arg.value.parameter, ".",  " = ").apply(i_arg.key)»«ENDIF»«i_arg.value.value.code.noTerminator»«IF i_arg.key < arguments.length - 1»,«ENDIF»
				«ENDFOR»	
			}
			''')
			
			return '''
			«constructedStruct»
			'''
		}
		return '''BROKEN MODEL''';
	}
	
	def boolean hasNamedMembers(EObject context, AbstractType type) {
		val eClass = context.eResource.constraintSystem.getUserData(type, BaseConstraintFactory.ECLASS_KEY);
		return #["NamedProductType", "StructureType"].findFirst[it == eClass] !== null;
	}
	
	@Traced def IGeneratorNode generateGeneratedFunctionCall(ElementReferenceExpression funCall, CodeWithContext target, GeneratedFunctionDefinition function) {
		val generator = registry.getGenerator(function);
		if(generator === null) {
			// contract: no generator means NOOP.
			return ''''''
		}
		'''«generator.generate(target, funCall).noTerminator»''';
	}
	
	@Traced dispatch def IGeneratorNode code(ElementReferenceExpression stmt) {
		val ref = stmt.reference
		val id = ref?.baseName
		
		val arguments = ExpressionUtils.getArgumentsOfElementReferenceExpression(stmt);
		

		if (stmt.operationCall) {
			if (ref instanceof VirtualFunction) {
				'''«generateVirtualFunctionCall(stmt, ref, arguments)»'''
			} else if (ref instanceof FunctionDefinition) {
				'''«ref.generateFunctionCall(cf('''NULL''').addHeader("stdlib.h", true), stmt)»'''
			} else if (ref instanceof GeneratedFunctionDefinition) {
				// target is null if we aren't part of an assignment
				'''«generateGeneratedFunctionCall(stmt, null, ref)»''';
			} else if(ref instanceof NativeFunctionDefinition) {
				if(ref.checked) {
					'''«ref.generateNativeFunctionCallChecked(cf('''NULL'''), stmt)»'''
				} else {
					'''«ref.generateNativeFunctionCallUnchecked(stmt)»'''
				}
			} else { 
				if(ref instanceof Modality || ref instanceof SignalInstance) {
					return '''''';
				}
				else {
				'''!UNKNOWN REF < EOBJECT!''';
				}
			}
		} else if (stmt.isArrayAccess && !(stmt.arraySelector.head instanceof ValueRange)) {
			
		} else if (id === null) {
			val nameFeature = stmt.reference.eClass.EAllStructuralFeatures.findFirst[x|x.name == 'name'];
			if (nameFeature === null) {
				'''/* unidentified element «stmt.reference» */'''
			} else {
				'''«stmt.reference.eGet(nameFeature)»'''
			}
		} else {
			'''«id»'''
		}
	}

	@Traced dispatch def IGeneratorNode code(DereferenceExpression e) {
		'''(*«e.expression.code»)'''
	}
	
	@Traced dispatch def IGeneratorNode code(ReferenceExpression e) {
		'''(&«e.variable.code»)'''
	}

	@Traced dispatch def IGeneratorNode code(ReturnValueExpression stmt) {
		return '''
			«_code(stmt as AssignmentExpression)»
			«codeReturnStatement(stmt)»
		'''
	}

	@Traced dispatch def IGeneratorNode code(ReturnStatement stmt) {
		'''
			«codeReturnStatement(stmt)»
		'''
	}
	@Traced def IGeneratorNode codeReturnStatement(EObject context) {
		'''
			«««If we are in try OR in catch we need to only exit the try/catch block, since we also need to execute finally.
			«IF ModelUtils.isInTryCatchFinally(context)»
				returnFromWithinTryCatch = true;
				break;
			«ELSE»
				return exception;
			«ENDIF»
		'''
	}
	
	@Traced dispatch def IGeneratorNode code(AssignmentExpression stmt) {
		return '''«stmt.initializationCode.noTerminator»;'''
	}

	@Traced dispatch def IGeneratorNode code(InterpolatedStringLiteral stmt) {
		// This method seems like dead code!
		/*
		 * InterpolatedStrings are a special case of an expression where the code generation must be devolved to
		 * the StringGenerator (i.e. the code generator registered at the generated-type string). Inelegantly, we
		 * explicitly encode this case and devolve code generation the registered code generator of the generated-type. 
		 */
		val type = BaseUtils.getType(stmt);
		if (TypeUtils.isGeneratedType(stmt.eResource, type)) {
			val generator = registry.getGenerator(stmt.eResource, type).castOrNull(AbstractTypeGenerator);
			if (generator !== null) {
				val varName = codeFragmentProvider.create('''«stmt»''');
				return '''«generator.generateExpression(stmt, varName, new CodeWithContext(type, Optional.empty, varName), AssignmentOperator.ASSIGN, null)»''';
			} else {
				throw new CoreException(
					new Status(IStatus.ERROR, "org.eclipse.mita.program",
						'String generator does not support inline interpolation'));
			}
		} else {
			throw new CoreException(
				new Status(IStatus.ERROR, "org.eclipse.mita.program",
					'Interpolated strings should be a generated type'));
		}
	}

	@Traced dispatch def IGeneratorNode code(Expression stmt) {
		'''ERROR: unsupported expression «stmt»'''
	}

	@Traced dispatch def IGeneratorNode code(ExpressionStatement stmt) {
		'''«stmt.expression.code.noTerminator»;'''
	}
	
	
	def IGeneratorNode generateFunCallStmt(CodeWithContext left, ElementReferenceExpression initialization) {
		val reference = initialization.reference;
		val arguments = ExpressionUtils.getArgumentsOfElementReferenceExpression(initialization);
		if (reference instanceof VirtualFunction) {
			return cf('''
				«left.code» = «generateVirtualFunctionCall(initialization, reference, arguments).noTerminator»;
			''')
		} else if (reference instanceof FunctionDefinition) {
			return cf('''
				«generateFunctionCall(reference, cf('''&«left.code»'''), initialization).noTerminator»;
			''')
		} else if (reference instanceof GeneratedFunctionDefinition) {
			return cf('''
				«generateGeneratedFunctionCall(initialization, left, reference)»;
			''')
		} else if(reference instanceof NativeFunctionDefinition) {
			if(reference.checked) {
				return cf('''
				«generateNativeFunctionCallChecked(reference, cf('''&«left.code»'''), initialization).noTerminator»;
				''')
			}
			else {
				return cf('''
				«left.code» = «generateNativeFunctionCallUnchecked(reference, initialization).noTerminator»;''')
			}
		}	
	}
	

	// TODO: remove code duplication with generateVariableDeclaration(...)
	dispatch def IGeneratorNode initializationCode(VariableDeclaration stmt) {
		val varName = cf('''«stmt.name»''');
		val rightSide = if(stmt.initialization !== null) {
			new CodeWithContext(BaseUtils.getType(stmt.initialization), Optional.of(stmt.initialization), cf(stmt.initialization.code));
		}
		return initializationCode(
			stmt, 
			varName, 
			new CodeWithContext(BaseUtils.getType(stmt), Optional.of(stmt), varName), 
			AssignmentOperator.ASSIGN, 
			rightSide,
			false
		);
	}
	
		dispatch def IGeneratorNode initializationCode(ReturnValueExpression expr) {
		val varName = cf('''«expr.varRef.code.noTerminator»''');
		return initializationCode(
			expr.varRef, 
			cf('''_result'''),
			new CodeWithContext(BaseUtils.getType(expr.varRef), Optional.of(expr.varRef), varName), 
			expr.operator, 
			new CodeWithContext(BaseUtils.getType(expr.expression), Optional.of(expr.expression), cf(expr.expression.code)), 
			true
		);
	}
	
//	public def IGeneratorNode initializationCode(EObject target, CodeFragment varName, AssignmentOperator op, Expression initialization, boolean alwaysGenerate) {
// 		return initializationCode(BaseUtils.getType(target), target, varName, op, initialization, alwaysGenerate);
// 	}

	dispatch def IGeneratorNode initializationCode(AssignmentExpression expr) {
		val varName = cf('''«expr.varRef.code.noTerminator»''');
		return initializationCode(
			expr.varRef, 
			varName,
			new CodeWithContext(BaseUtils.getType(expr.varRef), Optional.of(expr.varRef), varName), 
			expr.operator, 
			new CodeWithContext(BaseUtils.getType(expr.expression), Optional.of(expr.expression), cf(expr.expression.code)), 
			true
		);
	}
	def IGeneratorNode initializationCode(EObject context, CodeFragment tempVarName, CodeWithContext left, AssignmentOperator op, CodeWithContext right, boolean alwaysGenerate) {
		// TODO handle Optional.none
		val initialization = right?.obj?.orElse(null);	
		if (isGeneratedType(context, left.type)) {
			val generator = registry.getGenerator(context.eResource, left.type).castOrNull(AbstractTypeGenerator);
 
			if (initialization instanceof ElementReferenceExpression && (initialization as ElementReferenceExpression).isOperationCall) {
				return generateFunCallStmt(left, initialization as ElementReferenceExpression);
			} 
			return generator.generateExpression(context, tempVarName, left, op, right);
		} else if (initialization instanceof ElementReferenceExpression) {
			if(initialization.isOperationCall) {
				return generateFunCallStmt(left, initialization);	
			}
			else {
				return context.trace('''«left.code» «op» «right.code.noTerminator»;''');
			}
		} else if(initialization instanceof ModalityAccess) {
			return context.trace('''«left.code» «op» «right.code.noTerminator»;''');
		} else if(alwaysGenerate && right !== null) {
			return context.trace('''«left.code» «op» «right.code.noTerminator»;''');
		}
		return CodeFragment.EMPTY;
	}
		
	dispatch def IGeneratorNode code(ReturnParameterDeclaration stmt) {
		return CodeFragment.EMPTY;
	}
	
	dispatch def IGeneratorNode code(NoopStatement stmt) {
		return codeFragmentProvider.create();
	}
  
	dispatch def IGeneratorNode code(ExceptionBaseVariableDeclaration stmt) {
		return cf('''
				«exceptionGenerator.exceptionType» «stmt.name» = NO_EXCEPTION;
				«IF stmt.needsReturnFromTryCatch»
					bool returnFromWithinTryCatch = false;
				«ENDIF»
				
			''').addHeader('stdbool.h', true)
	}

	dispatch def IGeneratorNode code(VariableDeclaration stmt) {
		return generateVariableDeclaration(
			BaseUtils.getType(stmt), 
			stmt, 
			Optional.of(stmt),
			cf('''«stmt.name»'''), 
			stmt.initialization,
			stmt.eContainer instanceof Program
		);
	}
	def IGeneratorNode generateVariableDeclaration(AbstractType type, EObject context, Optional<VariableDeclaration> varDecl, CodeFragment varName, Expression initialization, boolean isTopLevel) {
		var result = context.trace;
		
		val typeIsSingleton = TypeUtils.getConstraintSystem(context.eResource)?.getUserData(type, BaseConstraintFactory.ECLASS_KEY) == "Singleton";
		if(typeIsSingleton) {
			// singletons have no representation in C for now since they are just some tag in enums with empty data.
			return result;
		}
		
		
		var initializationDone = false;
		
		// generate declaration
		// generated types

		if (TypeUtils.isGeneratedType(context, type)) {
			val generator = registry.getGenerator(context.eResource, type).castOrNull(AbstractTypeGenerator);
			result.children += generator.generateVariableDeclaration(type, context, varName, initialization, isTopLevel);
		} else if (initialization instanceof ElementReferenceExpression) {
			val ref = initialization.reference;
			// Assignment from functions is done by declaring, then passing in a reference
			if(initialization.operationCall && 
				// constructors of structural types are done directly
				!(ref instanceof TypeConstructor)
			) {
				result.children += cf('''«type.getCtype(context)» «varName»;''');
			} else {
				// copy assigmnent
				// since type != generatedType we can copy with assignment
				result.children += cf('''«type.getCtype(context)» «varName» = «initialization.code.noTerminator»;''');
				initializationDone = true;
			}
		// constant assignments and similar get here
		} else if(initialization instanceof ModalityAccess) {
			result.children += cf('''«type.getCtype(context)» «varName»;''');
		} 
		else {
			if (initialization !== null) {
				result.children += cf('''«type.getCtype(context)» «varName» = «initialization.code.noTerminator»;''');
			} else if (type instanceof ProdType || type instanceof org.eclipse.mita.base.typesystem.types.SumType) {
				result.children += cf('''«type.getCtype(context)» «varName» = {0};''');
			} else if (type instanceof NumericType) {
				result.children += cf('''«type.getCtype(context)» «varName» = 0;''');
			} else if(type instanceof AtomicType) {
				// init is zero, type is atomic, but not generated
				// -> type is bool
				if(type.name == "bool") {
					result.children += cf('''«type.getCtype(context)» «varName» = false;''');
				}
				else {
					result.children += cf('''«type.getCtype(context)» «varName» = ERROR unsupported initialization;''');
				} 
			} else {
				result.children += cf('''«type.getCtype(context)» «varName» = ERROR unsupported initialization;''');
			}
			// all of the above did initialization
			initializationDone = true;
		}
		// We can only generate declarative statements
		if(isTopLevel || initializationDone) {
			return result;
		}
		
		// generate initialization
		if(!initializationDone) {
			result.children += cf('''«"\n"»''');
			// TODO: remove code duplication with initializationCode(VariableDeclaration)
			result.children += initializationCode(
				context, 
				varName, 
				new CodeWithContext(type, varDecl.map[it], varName), 
				AssignmentOperator.ASSIGN, 
				if(initialization !== null) { new CodeWithContext(BaseUtils.getType(initialization), Optional.of(initialization), cf(initialization.code)) }, 
				false 
			).noNewline.noTerminator;
			result.children += cf('''«";"»''');		
		}
		
		return result;
	}

	@Traced dispatch def IGeneratorNode code(IfStatement stmt) {
		'''
			if(«stmt.condition.code.noTerminator»)
			«stmt.then.code»
			«FOR elif : stmt.elseIf»
				else if(«elif.condition.code.noTerminator»)
				«elif.then.code»
			«ENDFOR»
			«IF stmt.^else !== null»
				else
				«stmt.^else.code»
			«ENDIF»
		'''
	}

	@Traced dispatch def IGeneratorNode code(ThrowExceptionStatement stmt) {
		if (ModelUtils.isInTryCatchFinally(stmt)) {
			'''
				// THROW «stmt.exceptionType.name»
				exception = «cf('''«stmt.exceptionType.baseName»''').addHeader('MitaExceptions.h', true)»;
				break;
			'''
		} else {
			'''
				// THROW «stmt.exceptionType.name»
				return «cf('''«stmt.exceptionType.baseName»''').addHeader('MitaExceptions.h', true)»;
			'''
		}
	}
	
	dispatch def IGeneratorNode code(TypeSpecifier type) {
		return cf('''«getCtype(BaseUtils.getType(type), type)»''');
	}
	
	@Traced dispatch def IGeneratorNode code(TryStatement stmt) {
		val bool = cf('''bool''').addHeader('stdbool.h', true);
		'''
			// TRY
			returnFromWithinTryCatch = false;
			do
			«stmt.^try.code»
			while(false);
			«FOR idx_catchStmt : stmt.catchStatements.indexed»
				// CATCH «idx_catchStmt.value.exceptionType.name»
				«IF idx_catchStmt.key > 0»else «ENDIF»if(exception «IF idx_catchStmt.value.exceptionType.name == 'Exception'»!= NO_EXCEPTION«ELSE»== «idx_catchStmt.value.exceptionType.baseName»«ENDIF»)
				{
					exception = NO_EXCEPTION;
«««If we are in try OR in catch we need to only exit the try/catch block, since we also need to execute finally. Therefore we generate a for loop as well
					do
					«idx_catchStmt.value.body.code»
					while(«false»);
				}
			«ENDFOR»
			«IF stmt.^finally !== null»
				// FINALLY
				do
				«stmt.^finally.code»
				while(false);
			«ENDIF»
««« If we returned in a try-, catch- or finally-block, we only exited that block. Furthermore, if we didn't catch an exception, we need to fall through.
			if(returnFromWithinTryCatch || exception != NO_EXCEPTION) {
««« We might be in a nested try/etc.. In that case we should only break, and continue handling exceptions and executing finally.
			«IF ModelUtils.isInTryCatchFinally(stmt.eContainer)»
				break;
			«ELSE»
				return exception;
			«ENDIF»
			}
		'''
	}

	@Traced dispatch def IGeneratorNode code(WhileStatement stmt) {
		'''
			while(«stmt.condition.code.noTerminator»)
			«stmt.body.code»
			«IF ModelUtils.isInTryCatchFinally(stmt)»
			if(exception != NO_EXCEPTION) break;
			«ENDIF»
		'''
	}

	@Traced dispatch def IGeneratorNode code(ForStatement stmt) {
		val condition = stmt.condition.code.noTerminator;
		'''
			for(«FOR x : stmt.loopVariables SEPARATOR ' ,'»«x.code.noTerminator»«ENDFOR»; «condition»; «FOR x : stmt.postLoopStatements SEPARATOR ' ,'»«x.code.noTerminator»«ENDFOR»)
			«stmt.body.code»
			«IF ModelUtils.isInTryCatchFinally(stmt)»
			if(exception != NO_EXCEPTION) break;
			«ENDIF»
		'''
	}

	@Traced dispatch def IGeneratorNode code(ForEachStatement stmt) {
		'''
			// ERROR: for-each statements are not supported yet
		'''
	}

	@Traced dispatch def IGeneratorNode code(DoWhileStatement stmt) {
		'''
			do 
			«stmt.body.code»
			while(«stmt.condition.code.noTerminator»);
			«IF ModelUtils.isInTryCatchFinally(stmt)»
			if(exception != NO_EXCEPTION) break;
			«ENDIF»
		'''
	}

	@Traced dispatch def IGeneratorNode code(ConditionalExpression it) {
		'''«condition.code.noTerminator» ? «trueCase.code.noTerminator» : «falseCase.code»'''
	}

	@Traced dispatch def IGeneratorNode code(ProgramBlock stmt) {
		// TODO: analyze content and check for sensor access
		'''
			{
				«FOR x : stmt.content SEPARATOR '\n'»
					«x.code»
				«ENDFOR»
			}
		'''
	}

	@Traced dispatch def IGeneratorNode code(FunctionDefinition stmt) {
		'''
			«stmt.header.noTerminator»
			{
			«stmt.body.code.noBraces»
				return exception;
			}
		'''
	}
	
	@Traced dispatch def IGeneratorNode code(SourceCodeComment stmt) {
		'''
			/*
			«stmt.content»
			*/
		'''
	}

	@Traced dispatch def IGeneratorNode code(AbstractStatement stmt) {
		// fallback ... we haven't implemented the statement yet
		'''Unsuported statement: «stmt»'''
	}
		
	@Traced dispatch def IGeneratorNode code(WhereIsStatement stmt) {
		'''
		switch(«stmt.matchElement.code».tag) {
			«FOR isCase: stmt.isCases» 
			«isCase.code»
			«ENDFOR»
		}
		'''
	}
	@Traced dispatch def IGeneratorNode code(IsTypeMatchCase stmt) {
		val varType = stmt.productType;
		'''
		case «varType.enumName»: {
			«stmt.body.code.noBraces»
			break;
		}
		'''
	}
	
	@Traced dispatch def IGeneratorNode code(IsAssignmentCase stmt) {
		val varType = BaseUtils.getType(stmt.assignmentVariable);
		val where = stmt.eContainer as WhereIsStatement;
		'''
		case «varType.getEnumName(stmt)»: {
			«varType.getCtype(stmt)» «stmt.assignmentVariable.name» = «where.matchElement.code».data.«varType.getNameInStruct(stmt)»;
			«stmt.body.code.noBraces»
			break;
		}
		'''
	}
	
	@Traced dispatch def IGeneratorNode code(IsDeconstructionCase stmt) {
		val varType = stmt.productType;
		'''
		case «varType.enumName»: {
			«FOR deconstructor: stmt.deconstructors»
			«deconstructor.code»
			«ENDFOR»
			«stmt.body.code.noBraces»
			break;
		}
		'''
	}
	
	@Traced dispatch def IGeneratorNode code(IsOtherCase stmt) {
		'''
		default: {
			«stmt.body.code.noBraces»
			break;
		}
		'''
	}
	
	def Function<Integer, String> accessor(EObject context, SumAlternative productType, Parameter preferred, String prefix, String suffix) {
		[idx | 
			if(preferred !== null) {
				'''«prefix»«preferred.name»«suffix»'''	
			}
			else {
				ModelUtils.getAccessorParameters(productType)
					.transform[parameters | '''«prefix»«parameters.get(idx).baseName»«suffix»''']
					.or('''«prefix»_«idx»«suffix»''')
			} ]
	}
	
	@Traced dispatch def IGeneratorNode code(IsDeconstructor stmt) {
		val varType = BaseUtils.getType(stmt);
		val isDeconstructionCase = stmt.eContainer as IsDeconstructionCase;
		val isDeconstructionCaseType = isDeconstructionCase.productType;
		val where = isDeconstructionCase.eContainer as WhereIsStatement;
		val altAccessor = isDeconstructionCaseType.nameInStruct;
		val idx = isDeconstructionCase.deconstructors.indexOf(stmt);
		val productType = BaseUtils.getType(isDeconstructionCase.productType);

		val member = accessor(stmt, isDeconstructionCase.productType, stmt.productMember, ".", "").apply(idx);
		val realType = getRealType(stmt, productType);
		val hasAccessors = (productType instanceof ProdType && (productType as ProdType).typeArguments.size > 2);
		
		return '''«varType.getCtype(stmt)» «stmt.name» = «where.matchElement.code».data.«altAccessor»«IF hasAccessors»«member»«ENDIF»;'''

	}
	
	@Traced dispatch def IGeneratorNode code(LoopBreakerStatement stmt) {
		'''
		if(«stmt.condition.code.noTerminator»)
		{
			// loop condition still holds: continue the loop
		}
		else
		{
			// loop condition no longer holds: break the loop
			break;
		}
		'''
	}

	@Traced dispatch def header(FunctionDefinition definition) {
		// TODO handle type schemes properly
		// but *basically* a function with type parameters can't do anything with them except pass values through, so we *could* translate to void*
		// however that's like, java, so ...
		var _resultType = BaseUtils.getType(definition);
		if(_resultType instanceof TypeScheme) {
			_resultType = _resultType.on;
		}
		val resultType = _resultType;
		if(resultType instanceof FunctionType) {
			return '''«exceptionGenerator.exceptionType» «definition.baseName»(«resultType.to.getCtype(definition)»* _result«IF !definition.parameters.empty», «ENDIF»«FOR x : definition.parameters SEPARATOR ', '»«BaseUtils.getType(x).getCtype(definition)» «x.name»«ENDFOR»);'''
		}
		else {
			return '''!!!NOT A FUNCTION!!!'''
		}
	}
	
	dispatch def IGeneratorNode header(StructureType definition) {
		return structureTypeCode(definition);
	}
	
	def IGeneratorNode structureTypeCode(StructureType definition) {
		return structureTypeCodeDecl(definition, definition.parameters.map[it as Parameter].asEList, definition.structType);
	}
	
	def IGeneratorNode structureTypeCodeDecl(EObject obj, List<Parameter> parameters, CodeFragment typeName) {
		return structureTypeCodeReal(obj, parameters.map[new Pair(BaseUtils.getType(it).getCtype(obj), it.baseName)], typeName);
	
	}
	@Traced def IGeneratorNode structureTypeCodeReal(EObject obj, List<Pair<CodeFragment, String>> typesAndNames, CodeFragment typeName) {
		'''
		typedef struct {
			«FOR field : typesAndNames»
			«field.key» «field.value»;
			«ENDFOR»
		} «typeName»;
		'''
	} 
	
	@Traced dispatch def IGeneratorNode header(SumType definition) {
		val nonSingletonAlternatives = definition.alternatives.filter[!(it instanceof Singleton)];
		val hasOneMember = [ SumAlternative alt | 
			if(alt instanceof AnonymousProductType) {
				return alt.typeSpecifiers.length == 1;
			} else {
				return false;
			}
		]
		
		'''
		«FOR alternative: definition.alternatives.filter(NamedProductType)» 
		«structureTypeCodeDecl(alternative, alternative.parameters.map[it as Parameter].asEList, alternative.structType)»
		«ENDFOR»
		
		««« anonymous alternatives get tuple-like accessors (_1, _2, ...)
		«FOR alternative: definition.alternatives.filter(AnonymousProductType)»
		««« If we have only one typeSpecifier, we shorten to an alias, so we don't create a struct here 	
		«IF alternative.typeSpecifiers.length > 1»
		«structureTypeCodeReal(alternative, alternative.typeSpecifiers.indexed.map[new Pair(BaseUtils.getType(it.value).getCtype(definition), '''_«it.key»''')].toList, alternative.structType)»
		«ENDIF»		
		«ENDFOR»
		
		typedef enum {
			«FOR alternative: definition.alternatives SEPARATOR(",")»
			«alternative.enumName»
			«ENDFOR»
		} «definition.enumName»;
		
		typedef struct {
			«definition.enumName» tag;
			union {
				«FOR alternative: nonSingletonAlternatives»«BaseUtils.getType(alternative).getCtype(definition)» «alternative.nameInStruct»;
			«ENDFOR»
			} data;
		} «definition.structType»;
		'''
	}

	@Traced dispatch def header(EnumerationType definition) {
		'''
			typedef enum {
				«FOR item : definition.enumerator SEPARATOR ',\n'»«item.baseName»«ENDFOR»
			} «definition.baseName»;
		'''
	}
	
	@Traced def generateNativeFunctionCallChecked(NativeFunctionDefinition op, IGeneratorNode firstArg, ArgumentExpression args) {
		val call = codeFragmentProvider
			.create(generateFunctionCall(op, firstArg, args) as CompositeGeneratorNode)
			.addHeader(op.header, true);
		return '''«call»''';
	}
	
	@Traced def generateNativeFunctionCallUnchecked(NativeFunctionDefinition op, ArgumentExpression argExpression) {
		val arguments = ExpressionUtils.getArgumentsOfElementReferenceExpression(argExpression);
		val call = codeFragmentProvider
			.create('''«op.name»(«FOR arg : ExpressionUtils.getSortedArguments(op.parameters, arguments) SEPARATOR ', '»«arg.value.code.noTerminator»«ENDFOR»)''')
			.addHeader(op.header, true);
		return '''«call»'''
	}
	
	@Traced def generateFunctionCall(Operation op, IGeneratorNode firstArg, ArgumentExpression argExpression) {
		val arguments = ExpressionUtils.getArgumentsOfElementReferenceExpression(argExpression);
		'''

		exception = «op.baseName»(«IF firstArg !== null»«firstArg.noTerminator»«IF !arguments.empty», «ENDIF»«ENDIF»«FOR arg : ExpressionUtils.getSortedArguments(op.parameters, arguments) SEPARATOR ', '»«arg.value.code.noTerminator»«ENDFOR»);
		«generateExceptionHandler(argExpression, 'exception')»
		'''

	}

	private def getCtype(AbstractType type, EObject context) {
		val result = if(type instanceof TypeVariable) {
			cf('''void*''') 
		} 
		else {
			typeGenerator.code(context, type);	
		}
		val includeHeader = TypeUtils.getConstraintSystem(context.eResource)?.getUserData(type, BaseConstraintFactory.INCLUDE_HEADER_KEY);
		val userIncludeStr = TypeUtils.getConstraintSystem(context.eResource)?.getUserData(type, BaseConstraintFactory.INCLUDE_IS_USER_INCLUDE_KEY);
		val userInclude = if(!userIncludeStr.nullOrEmpty) {
			Boolean.getBoolean(userIncludeStr);
		}
		else {
			false;
		}
		if(includeHeader !== null) {
			result.addHeader(includeHeader, userInclude);
		}
		return result;
		
	}
}
