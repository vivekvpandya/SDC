module d.llvm.type;

import d.llvm.codegen;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import d.exception;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMTypeRef[ClassDeclaration] classes;
	private LLVMValueRef[ClassDeclaration] classInit;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			throw new CompileException(t.location, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	LLVMTypeRef visit(SymbolType t) {
		return pass.visit(t.symbol);
	}
	
	LLVMTypeRef visit(ClassType t) {
		return visit(t.dclass);
	}
	
	LLVMTypeRef visit(ClassDeclaration c) {
		if (auto t = c in classes) {
			return *t;
		}
		
		auto llvmStruct = LLVMStructCreateNamed(context, cast(char*) c.mangle.toStringz());
		auto structPtr = LLVMPointerType(llvmStruct, 0);
		classes[c] = structPtr;
		
		// TODO: typeid instead of null.
		auto vtbl = [LLVMConstNull(LLVMPointerType(LLVMInt8TypeInContext(context), 0))];
		LLVMValueRef[] fields = [null];
		foreach(member; c.members) {
			if (auto m = cast(MethodDeclaration) member) {
				auto oldBody = m.fbody;
				scope(exit) m.fbody = oldBody;
				
				m.fbody = null;
				
				vtbl ~= pass.visit(m);
			} else if(auto f = cast(FieldDeclaration) member) {
				if(f.index > 0) {
					fields ~= pass.visit(f.value);
				}
			}
		}
		
		auto vtblTypes = vtbl.map!(m => LLVMTypeOf(m)).array();
		auto vtblStruct = LLVMStructCreateNamed(context, cast(char*) (c.mangle ~ "__vtbl").toStringz());
		LLVMStructSetBody(vtblStruct, vtblTypes.ptr, cast(uint) vtblTypes.length, false);
		
		auto vtblPtr = LLVMAddGlobal(dmodule, vtblStruct, (c.mangle ~ "__vtblZ").toStringz());
		LLVMSetInitializer(vtblPtr, LLVMConstNamedStruct(vtblStruct, vtbl.ptr, cast(uint) vtbl.length));
		LLVMSetGlobalConstant(vtblPtr, true);
		
		// Set vtbl.
		fields[0] = vtblPtr;
		auto initTypes = fields.map!(f => LLVMTypeOf(f)).array();
		LLVMStructSetBody(llvmStruct, initTypes.ptr, cast(uint) initTypes.length, false);
		
		auto initPtr = LLVMAddGlobal(dmodule, llvmStruct, (c.mangle ~ "__initZ").toStringz());
		LLVMSetInitializer(initPtr, LLVMConstNamedStruct(llvmStruct, fields.ptr, cast(uint) fields.length));
		LLVMSetGlobalConstant(initPtr, true);
		
		classInit[c] = initPtr;
		
		return structPtr;
	}
	
	LLVMValueRef getClassInit(ClassDeclaration c) {
		return classInit[c];
	}
	
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1TypeInContext(context);
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) with(Integer) {
				case Byte, Ubyte :
					return LLVMInt8TypeInContext(context);
				
				case Short, Ushort :
					return LLVMInt16TypeInContext(context);
				
				case Int, Uint :
					return LLVMInt32TypeInContext(context);
				
				case Long, Ulong :
					return LLVMInt64TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) with(Float) {
				case Float :
					return LLVMFloatTypeInContext(context);
				
				case Double :
					return LLVMDoubleTypeInContext(context);
				
				case Real :
					return LLVMX86FP80TypeInContext(context);
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) with(Character) {
				case Char :
					return LLVMInt8TypeInContext(context);
				
				case Wchar :
					return LLVMInt16TypeInContext(context);
				
				case Dchar :
					return LLVMInt32TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidTypeInContext(context);
	}
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.type);
		
		if(LLVMGetTypeKind(pointed) == LLVMTypeKind.Void) {
			pointed = LLVMInt8TypeInContext(context);
		}
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		LLVMTypeRef[2] types;
		types[0] = LLVMInt64TypeInContext(context);
		types[1] = LLVMPointerType(visit(t.type), 0);
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(StaticArrayType t) {
		auto type = visit(t.type);
		auto size = pass.visit(t.size);
		
		return LLVMArrayType(type, cast(uint) LLVMConstIntGetZExtValue(size));
	}
	
	LLVMTypeRef visit(EnumType t) {
		return visit(t.type);
	}
	
	private auto buildParameterType(Parameter p) {
		auto type = visit(p.type);
		
		if(p.isReference) {
			type = LLVMPointerType(type, 0);
		}
		
		return type;
	}
	
	LLVMTypeRef visit(FunctionType t) {
		auto params = t.parameters.map!(p => buildParameterType(p)).array();
		
		return LLVMPointerType(LLVMFunctionType(visit(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic), 0);
	}
	
	LLVMTypeRef visit(DelegateType t) {
		LLVMTypeRef[] params;
		params.length = t.parameters.length + 1;
		params[0] = buildParameterType(t.context);
		
		foreach(i, p; t.parameters) {
			params[i + 1] = buildParameterType(p);
		}
		
		auto fun = LLVMFunctionType(visit(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic);
		
		LLVMTypeRef[2] types;
		types[0] = LLVMPointerType(fun, 0);
		types[1] = params[0];
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
}
