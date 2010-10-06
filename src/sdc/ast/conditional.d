/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.conditional;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.sdcmodule;
import sdc.ast.statement;
import sdc.ast.attribute;


enum ConditionalDeclarationType
{
    Block,
    VersionSpecification,
    DebugSpecification,
}

class ConditionalDeclaration : Node
{
    ConditionalDeclarationType type;
    Condition condition;
    DeclarationBlock thenBlock;  // Optional.
    DeclarationBlock elseBlock;  // Optional.
    Node specification;  // Optional.
}

class ConditionalStatement : Node
{
    Condition condition;
    NoScopeNonEmptyStatement thenStatement;
    NoScopeNonEmptyStatement elseStatement;  // Optional.
}

enum ConditionType
{
    Version,
    Debug,
    StaticIf
}

class Condition : Node
{
    ConditionType conditionType;
    Node condition;
}

enum VersionConditionType
{
    Integer,
    Identifier,
    Unittest
}

class VersionCondition : Node
{
    VersionConditionType type;
    IntegerLiteral integer;  // Optional.
    Identifier identifier;  // Optional.
}

enum SpecificationType
{
    Identifier,
    Integer
}

// version = foo
class VersionSpecification : Node
{
    SpecificationType type;
    Node node;
}

enum DebugConditionType
{
    Simple,
    Integer,
    Identifier
}

class DebugCondition : Node
{
    DebugConditionType type;
    IntegerLiteral integer;  // Optional.
    Identifier identifier;  // Optional.
}

// debug = foo
class DebugSpecification : Node
{
    SpecificationType type;
    Node node;
}

class StaticIfCondition : Node
{
    AssignExpression expression;
}
