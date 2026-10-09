// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Komeiji-Shiki and contributors

using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Text.Json;

// 只读取程序集元数据和指令中的常量，不加载或执行 Mod 的代码。
using var stream = File.OpenRead(args[0]);
using var pe = new PEReader(stream);
var metadata = pe.GetMetadataReader();
var opcodes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
    .Where(field => field.FieldType == typeof(OpCode))
    .Select(field => (OpCode)field.GetValue(null)!)
    .ToDictionary(opcode => unchecked((ushort)opcode.Value));
var methods = new Dictionary<int, List<Instruction>>();
foreach (var handle in metadata.MethodDefinitions)
{
    var method = metadata.GetMethodDefinition(handle);
    if (method.RelativeVirtualAddress != 0)
        methods[MetadataTokens.GetToken(handle)] = Decode(pe.GetMethodBody(method.RelativeVirtualAddress).GetILBytes()!);
}
var frameMethods = new Dictionary<int, Cue>();
foreach (var (token, instructions) in methods)
{
    var frames = new List<Frame>();
    string? path = null;
    float? seconds = null;
    var integer = 0;
    var loop = false;
    foreach (var instruction in instructions)
    {
        if (instruction.Code == OpCodes.Ldstr)
            path = metadata.GetUserString(MetadataTokens.UserStringHandle((int)instruction.Value! & 0x00ffffff));
        else if (instruction.Code == OpCodes.Ldc_R4)
            seconds = (float)instruction.Value!;
        else if (instruction.Code == OpCodes.Ldc_R8)
            seconds = (float)(double)instruction.Value!;
        else if (instruction.Code == OpCodes.Ldc_I4_0 || instruction.Code == OpCodes.Ldc_I4_1)
            integer = instruction.Code == OpCodes.Ldc_I4_1 ? 1 : 0;
        else if (instruction.Code == OpCodes.Call || instruction.Code == OpCodes.Callvirt)
        {
            var member = Member((int)instruction.Value!);
            if (member.Type == "VisualFrameSequenceBuilder" && member.Name == "Frame"
                && path?.StartsWith("res://") == true && seconds > 0)
            {
                frames.Add(new Frame(path, seconds.Value));
                path = null;
                seconds = null;
            }
            if (member.Type == "VisualFrameSequenceBuilder" && member.Name == "Loop")
                loop = integer != 0;
        }
    }
    if (frames.Count > 0)
        frameMethods[token] = new Cue("", loop, frames);
}
var scenes = new Dictionary<string, List<Cue>>();
foreach (var instructions in methods.Values)
{
    var strings = new List<string>();
    var cues = new List<Cue>();
    string? latest = null;
    string? combatScene = null;
    int? function = null;
    foreach (var instruction in instructions)
    {
        if (instruction.Code == OpCodes.Ldstr)
        {
            latest = metadata.GetUserString(MetadataTokens.UserStringHandle((int)instruction.Value! & 0x00ffffff));
            strings.Add(latest);
        }
        else if (instruction.Code == OpCodes.Ldftn || instruction.Code == OpCodes.Ldvirtftn)
            function = (int)instruction.Value!;
        else if (instruction.Code == OpCodes.Call || instruction.Code == OpCodes.Callvirt || instruction.Code == OpCodes.Newobj)
        {
            var member = Member((int)instruction.Value!);
            if (member.Type == "CharacterSceneAssetSet" && member.Name == ".ctor")
            {
                var paths = strings.Where(value => value.StartsWith("res://") && value.EndsWith(".tscn")).TakeLast(4).ToArray();
                if (paths.Length == 4)
                    combatScene = paths[0];
            }
            if (member.Type == "VisualCueSetBuilder" && member.Name == "Sequence" && latest != null
                && function.HasValue && frameMethods.TryGetValue(function.Value, out var cue))
            {
                cues.Add(cue with { name = latest });
                function = null;
            }
        }
    }
    if (combatScene != null && cues.Count > 0)
        scenes[combatScene] = cues;
}
Console.WriteLine(JsonSerializer.Serialize(scenes));

(string Type, string Name) Member(int token)
{
    var handle = MetadataTokens.EntityHandle(token);
    if (handle.Kind == HandleKind.MethodSpecification)
        return Member(MetadataTokens.GetToken(metadata.GetMethodSpecification((MethodSpecificationHandle)handle).Method));
    if (handle.Kind == HandleKind.MethodDefinition)
    {
        var definition = metadata.GetMethodDefinition((MethodDefinitionHandle)handle);
        return (metadata.GetString(metadata.GetTypeDefinition(definition.GetDeclaringType()).Name), metadata.GetString(definition.Name));
    }
    if (handle.Kind != HandleKind.MemberReference)
        return ("", "");
    var reference = metadata.GetMemberReference((MemberReferenceHandle)handle);
    var type = reference.Parent.Kind switch
    {
        HandleKind.TypeReference => metadata.GetString(metadata.GetTypeReference((TypeReferenceHandle)reference.Parent).Name),
        HandleKind.TypeDefinition => metadata.GetString(metadata.GetTypeDefinition((TypeDefinitionHandle)reference.Parent).Name),
        _ => ""
    };
    return (type, metadata.GetString(reference.Name));
}

List<Instruction> Decode(byte[] bytes)
{
    var result = new List<Instruction>();
    var offset = 0;
    while (offset < bytes.Length)
    {
        ushort code = bytes[offset++];
        if (code == 0xfe)
            code = (ushort)(0xfe00 | bytes[offset++]);
        var opcode = opcodes[code];
        object? operand = null;
        var size = opcode.OperandType switch
        {
            OperandType.InlineNone => 0,
            OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar => 1,
            OperandType.InlineVar => 2,
            OperandType.InlineI8 or OperandType.InlineR => 8,
            OperandType.InlineSwitch => 4 + 4 * BitConverter.ToInt32(bytes, offset),
            _ => 4
        };
        if (opcode.OperandType == OperandType.ShortInlineR)
            operand = BitConverter.ToSingle(bytes, offset);
        else if (opcode.OperandType == OperandType.InlineR)
            operand = BitConverter.ToDouble(bytes, offset);
        else if (size == 4)
            operand = BitConverter.ToInt32(bytes, offset);
        result.Add(new Instruction(opcode, operand));
        offset += size;
    }
    return result;
}

record Instruction(OpCode Code, object? Value);
record Frame(string path, float seconds);
record Cue(string name, bool loop, List<Frame> frames);
