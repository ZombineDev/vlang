// Copyright: Coverify Systems Technology 2014
// License:   Distributed under the Boost Software License, Version 1.0.
//            (See accompanying file LICENSE_1_0.txt or copy at
//            http://www.boost.org/LICENSE_1_0.txt)
// Authors:   Puneet Goel <puneet@coverify.com>

// VCD Parser

// A VCD object corresponds to a VCD file
module esdl.vcd.parse;

import esdl.data.bvec;
import esdl.data.bstr;
import esdl.data.time;

import std.conv: to;
import std.string: isNumeric;	// required for timeScale

// beyond this size the parser would create a logicstring instead of
// an lvec for storing data.
enum uint MaxVectorSize = 4096;

enum SCOPE_TYPE: byte
  {   BEGIN,
      FORK,
      FUNCTION,
      MODULE,
      TASK,
      }

enum VAR_TYPE: byte
  {   EVENT,
      INTEGER,
      PARAMETER,
      REAL,
      REALTIME,
      REG,
      SUPPLY0,
      SUPPLY1,
      TIME,
      TRI,
      TRIAND,
      TRIOR,
      TRIREG,
      TRI0,
      TRI1,
      WAND,
      WIRE,
      WOR,
      }

class VcdNode
{
  string _name;
  // root will have null parent
  VcdScope _parent;
  VCD      _vcd;
  this(VcdScope parent, VCD vcd) {
    _parent = parent;
    _vcd    = vcd;
    if(_parent !is null) {	// null for _root scope
      _parent._children ~= this;
    }
  }
}

class VcdScope: VcdNode
{
  // keep this as a dynamic array so that sorting is easy
  string _scopeType;		// keep is string for flexibility
  VcdNode[] _children;
  this(VcdScope parent, VCD vcd) {
    super(parent, vcd);
  }
}

abstract class VcdVar: VcdNode
{
  uint _size;
  this(VcdScope parent, VCD vcd, uint size) {
    super(parent, vcd);
    _size = size;
  }

  abstract void addScalarValChange(uint timeStep, char value);
  abstract void addVectorValChange(uint timeStep, string value);
  abstract void addLogicStringValChange(uint timeStep, string value);
  abstract void addRealValChange(uint timeStep, string value);
  abstract void addCommandValChange(uint timeStep, SIM_COMMAND value);
  abstract void addStringValChange(uint timeStep, string value);

  // Takes too much memory
  // static VcdVar makeVarVec(size_t A=1, size_t N=64, size_t Z=128)
  //   (VcdScope parent, string name, uint size) {
  //   if(size > Z) {
  //     assert(false, "Can not handle variables of size > 65536");
  //   }
  //   else if(size == N) {
  //     alias T = ulvec!N;
  //     return new VcdVecWave!T(parent, name, size);
  //   }
  //   else if(size < N) {
  //     return makeVarVec!(A, (N+A)/2, N)(parent, name, size);
  //   }
  //   else {
  //     return makeVarVec!(N, (N+Z)/2, Z)(parent, name, size);
  //   }
  // }

  static VcdVar makeVarVec(size_t N=64)
    (VcdScope parent, VCD vcd, string name, uint size) {
    static if(N <= MaxVectorSize) {
      static if(N == 64) {
	if(size <= 8) {
	  alias T = ulvec!8;
	  return new VcdVecWave!T(parent, vcd, name, size);
	}
	else if(size <= 16) {
	  alias T = ulvec!16;
	  return new VcdVecWave!T(parent, vcd, name, size);
	}
	else if(size <= 32) {
	  alias T = ulvec!32;
	  return new VcdVecWave!T(parent, vcd, name, size);
	}
	else if(size <= 64) {
	  alias T = ulvec!64;
	  return new VcdVecWave!T(parent, vcd, name, size);
	}
	else {
	  return makeVarVec!(N+64)(parent, vcd, name, size);
	}
      }
      else {			// static if(N != 64)
	if(size <= N) {	
	  alias T = ulvec!N;
	  return new VcdVecWave!T(parent, vcd, name, size);
	}
	else {
	  return makeVarVec!(N+64)(parent, vcd, name, size);
	}
      }
    }
    else {
      return new VcdVecWave!lstr(parent, vcd, name, size);
    }
  }
}

enum SIM_COMMAND: byte
  {   DUMPALL,
      DUMPOFF,
      DUMPON,
      DUMPVARS,
      COMMENT,
      }

// V is a type and can be
// bool     -- EVENT
// ulvec!32 -- INTEGER
// ulvec!n  -- PARAMETER, REG, SUPPLY0, SUPPLY1, TRI, TRIAND, TRIOR, TRIREG
//             TRI0, TRI1, WAND, WIRE, WOR
// ulvec!64 -- time
// real     -- REAL
// real     -- REALTIME

struct VcdVecVal(V)
{
  uint _timeStep;
  V     _val;
  this(uint timeStep, V value) {
    _timeStep = timeStep;
    _val = value;
  }
}

class VcdVecWave(V): VcdVar
{
  VcdVecVal!V _wave[];
  this(VcdScope parent, VCD vcd, string name, uint size) {
    super(parent, vcd, size);
  }

  override void addScalarValChange(uint timeStep, char value) {
    static if(isBitVector!V || is(V == bool)) {
      if(_size != 1) {
	assert(false, "Scalar Value provided for a variable of size: " ~
	       _size.to!string);
      }
      static if(is(V == bool)) { // for events
	if(value != '1') {
	  assert(false, "Illegal value for an event");
	}
	else {
	  _wave ~= VcdVecVal!bool(timeStep, true);
	}
      }
      else {
	switch(value) {
	case '0':
	  V val = 0;
	  _wave ~= VcdVecVal!V(timeStep, val);
	  break;
	case '1':
	  V val = 1;
	  _wave ~= VcdVecVal!V(timeStep, val);
	  break;
	case 'x':
	case 'X':
	  V val = LOGIC_X;
	  _wave ~= VcdVecVal!V(timeStep, val);
	  break;
	case 'z':
	case 'Z':
	  V val = LOGIC_Z;
	  _wave ~= VcdVecVal!V(timeStep, val);
	  break;
	default:
	  assert(false, "Unrecognized Scalar Value: " ~ value);
	}
      }
    }
    else {
      assert(false, "addScalarValChange applicable only to bitvectors or bool");
    }
  }
  
  override void addVectorValChange(uint timeStep, string value) {
    static if(isBitVector!V) {
      V val;			// all 0s
      // left fill bit in value -- 
      char leftFill;
      // 0th char is 'b' or 'B'      
      if(value[0] != 'b' && value[0] != 'B') {
	assert(false, "Illegal vector value: " ~ value);
      }
      switch(value[1]) {
      case '0':
      case '1':
	leftFill = '0';
	break;
      case 'x':
      case 'X':
	leftFill = 'X';
	break;
      case 'z':
      case 'Z':
	leftFill = 'Z';
	break;
      default:
	assert(false, "Illegal vector value: " ~ value);
      }
      
      for (uint n=0; n!=_size; ++n) {
	char nBit;
	if(value.length > n + 1) {
	  nBit = value[$-1-n];
	}
	else {
	  nBit = leftFill;
	}
	switch(nBit) {
	case '0':
	  val[n] = LOGIC_0;
	  break;
	case '1':
	  val[n] = LOGIC_1;
	  break;
	case 'x':
	case 'X':
	  val[n] = LOGIC_X;
	  break;
	case 'z':
	case 'Z':
	  val[n] = LOGIC_Z;
	  break;
	default:
	  assert(false, "Illegal vector value: " ~ value);
	}
      }
      _wave ~= VcdVecVal!V(timeStep, val);
    }
    else {
	assert(false, "UNEXPECTED type for addVectorValChange: " ~ V.stringof);
      }
    
  }
  
  override void addLogicStringValChange(uint timeStep, string value) {
    static if(is(V == lstr)) {
      V val;			// all 0s
      val.length = _size;
      // left fill bit in value -- 
      char leftFill;
      // 0th char is 'b' or 'B'      
      if(value[0] != 'b' && value[0] != 'B') {
	assert(false, "Illegal vector value: " ~ value);
      }
      switch(value[1]) {
      case '0':
      case '1':
	leftFill = '0';
	break;
      case 'x':
      case 'X':
	leftFill = 'X';
	break;
      case 'z':
      case 'Z':
	leftFill = 'Z';
	break;
      default:
	assert(false, "Illegal vector value: " ~ value);
      }
      
      for (uint n=0; n!=_size; ++n) {
	char nBit;
	if(value.length > n + 1) {
	  nBit = value[$-1-n];
	}
	else {
	  nBit = leftFill;
	}
	switch(nBit) {
	case '0':
	  val[n] = LOGIC_0;
	  break;
	case '1':
	  val[n] = LOGIC_1;
	  break;
	case 'x':
	case 'X':
	  val[n] = LOGIC_X;
	  break;
	case 'z':
	case 'Z':
	  val[n] = LOGIC_Z;
	  break;
	default:
	  assert(false, "Illegal vector value: " ~ value);
	}
      }
      _wave ~= VcdVecVal!V(timeStep, val);
    }
    else {
      assert(false, "UNEXPECTED type for addVectorValChange: " ~ V.stringof);
    }
    
  }
  
  override void addRealValChange(uint timeStep, string value) {
    static if(is(V == real)) {
      if(value[0] != 'r' && value[0] != 'R') {
	assert(false, "Illegal real value: " ~ value);
      }
      if(!isNumeric(value[1..$])) {
	assert(false, "Illegal real value: " ~ value);
      }
      real val = value[1..$].to!real;
      _wave ~= VcdVecVal!V(timeStep, val);
    }
    else {
	assert(false, "UNEXPECTED type for addRealValChange: " ~ V.stringof);
      }
  }
  
  override void addStringValChange(uint timeStep, string value) {
    static if(is(V == string)) {
      _wave ~= VcdVecVal!string(timeStep, value);
    }
    else {
	assert(false, "UNEXPECTED type for addStringValChange: " ~ V.stringof);
      }
  }
  
  override void addCommandValChange(uint timeStep, SIM_COMMAND value) {
    static if(is(V == SIM_COMMAND)) {
      _wave ~= VcdVecVal!SIM_COMMAND(timeStep, value);
    }
    else {
      assert(false, "UNEXPECTED type for addCommandValChange: " ~ V.stringof);
    }
  }
  
};

class VCD
{
  public this(string name) {
    _file = new VcdFile(name);
    _timeStamps ~= 0;
    _comments = new VcdVecWave!string(null, this, "comments", 1);
    _commands = new VcdVecWave!SIM_COMMAND(null, this, "commands", 1);
    _dumpon =   new VcdVecWave!bool(null, this, "$dumpon", 1);
    _dumpoff =  new VcdVecWave!bool(null, this, "$dumpoff", 1);
    _dumpall =  new VcdVecWave!bool(null, this, "$dumpall", 1);
    _dumpvars = new VcdVecWave!bool(null, this, "$dumpvars", 1);
    parseDeclarations();
    parseSimulation();
  }
  VcdFile _file;
  string  _date;
  string  _version;
  Time    _timeScale;
  // comment in the definition area
  string  _comment;
  VcdScope _root;
  // commands along with timestamps
  VcdVecWave!SIM_COMMAND _commands;
  VcdVecWave!bool        _dumpon;
  VcdVecWave!bool        _dumpoff;
  VcdVecWave!bool        _dumpall;
  VcdVecWave!bool        _dumpvars;
  // comments in the dump area along with timestamps
  VcdVecWave!string      _comments;

  // associative array that keeps a lookup for the string symbols and
  // the corresponding variable
  VcdVar[string] _lookup;

  ulong[] _timeStamps;

  static VAR_TYPE[string] _varTypeLookup;
  static SIM_COMMAND[string] _commandTypeLookup;

  static this() {
    _varTypeLookup = ["event":VAR_TYPE.EVENT,
		      "integer":VAR_TYPE.INTEGER,
		      "parameter":VAR_TYPE.PARAMETER,
		      "real":VAR_TYPE.REAL,
		      "realtime":VAR_TYPE.REALTIME,
		      "reg":VAR_TYPE.REG,
		      "supply0":VAR_TYPE.SUPPLY0,
		      "supply1":VAR_TYPE.SUPPLY1,
		      "time":VAR_TYPE.TIME,
		      "tri":VAR_TYPE.TRI,
		      "triand":VAR_TYPE.TRIAND,
		      "trior":VAR_TYPE.TRIOR,
		      "trireg":VAR_TYPE.TRIREG,
		      "tri0":VAR_TYPE.TRI0,
		      "tri1":VAR_TYPE.TRI1,
		      "wand":VAR_TYPE.WAND,
		      "wire":VAR_TYPE.WIRE,
		      "wor":VAR_TYPE.WOR,
		      ];
    _commandTypeLookup = ["$dumpall":SIM_COMMAND.DUMPALL,
			  "$dumpoff":SIM_COMMAND.DUMPOFF,
			  "$dumpon":SIM_COMMAND.DUMPON,
			  "$dumpvars":SIM_COMMAND.DUMPVARS,
			  ];
  }

  // enum DECLARATION_COMMAND: byte
  //   {   NONE,
  // 	COMMENT,
  // 	DATE,
  // 	ENDDEFINITIONS,
  // 	SCOPE,
  // 	TIMESCALE,
  // 	UPSCOPE,
  // 	VAR,
  // 	VERSION,
  // 	}

  void parseDeclarationComment() {
    string word;
    while((word = _file.nextWord()) != "$end") {
      _comment ~= word;
      _comment ~= " ";
    }
    _comment.length -= 1;
    return;
  }

  void parseDate() {
    string word;
    while((word = _file.nextWord()) != "$end") {
      _date ~= word;
      _date ~= " ";
    }
    _date.length -= 1;
    return;
  }
  
  void parseVersion() {
    string word;
    while((word = _file.nextWord()) != "$end") {
      _version ~= word;
      _version ~= " ";
    }
    _version.length -= 1;
    return;
  }
  
  void parseTimeScale() {
    string word;
    int val;

    word = _file.nextWord();
    if(isNumeric(word)) {
      val = word.to!int;
      word = _file.nextWord();
    }
    // cover the case where time is specified as 1s (without space)
    else if(isNumeric(word[0..$-1])) {
      val = word[0..$-1].to!int;
      word = word[$-1..$];
    }
    // cover the case where time is specified as 1ns (without space)
    else if(isNumeric(word[0..$-2])) {
      val = word[0..$-2].to!int;
      word = word[$-2..$];
    }
    else {
      assert(false, _file.errorString);
    }

    if(word == "s") {
      _timeScale = val.sec;
    }
    else if(word == "ms") {
      _timeScale = val.msec;
    }
    else if(word == "us") {
      _timeScale = val.usec;
    }
    else if(word == "ns") {
      _timeScale = val.nsec;
    }
    else if(word == "ps") {
      _timeScale = val.psec;
    }
    else if(word == "fs") {
      _timeScale = val.fsec;
    }
    else {
      assert(false, _file.errorString);
    }

    word = _file.nextWord();
    if(word != "$end") {
      assert(false, _file.errorString);
    }
  }

  void parseVar(VcdScope currScope) {
    VAR_TYPE varType;
    uint size;
    string id;
    string name;
    auto typeStr = _file.nextWord();
    auto vt = typeStr in _varTypeLookup;
    if(vt is null) {
      assert(false, _file.errorString);
    }
    else {
      varType = *vt;
    }
    auto sizeStr = _file.nextWord();
    if(! isNumeric(sizeStr)) {
      assert(false, _file.errorString);
    }
    else {
      size = sizeStr.to!int;
    }
    id   = _file.nextWord().dup;
    name = _file.nextWord().dup;
    string arrayInfo;
    if((arrayInfo = _file.nextWord()) != "$end") { // this could be the array info
      name ~= arrayInfo;
      if(_file.nextWord() != "$end") {
	assert(false, _file.errorString);
      }
    }
    VcdVar var;
    switch(varType) {
    case VAR_TYPE.EVENT:
      var = new VcdVecWave!bool(currScope, this, name, 1);
      break;
    case VAR_TYPE.REAL:
    case VAR_TYPE.REALTIME:
      var = new VcdVecWave!real(currScope, this, name, 1);
      break;
    default:			// ulvec!size
      // if(size >= 1024) assert(false, "Too big vector size 1024");
      // mixin(genVarCode(0, 64));
      var = VcdVar.makeVarVec(currScope, this, name, size);
      if(id in _lookup) {
	assert(false, "Duplicate Variable ID: " ~ id);
      }
      else {
	_lookup[id] = var;
      }
      break;
    }
  }
  
// V is a type and can be
// bool     -- EVENT
// ulvec!32 -- INTEGER
// ulvec!n  -- PARAMETER, REG, SUPPLY0, SUPPLY1, TRI, TRIAND, TRIOR, TRIREG
//             TRI0, TRI1, WAND, WIRE, WOR
// ulvec!64 -- TIME
// real     -- REAL
// real     -- REALTIME

  void parseScope(VcdScope currScope, ) {
    currScope._scopeType = _file.nextWord().dup;
    currScope._name = _file.nextWord().dup;
    if(_file.nextWord() != "$end") {
      assert(false, _file.errorString);
    }
    while(true) {
      auto word = _file.nextWord();
      if(word == "$scope") {
	VcdScope child = new VcdScope(currScope, this);
	parseScope(child);
      }
      else if(word == "$upscope") {
	if(_file.nextWord() != "$end") {
	  assert(false, _file.errorString);
	}
	else return;
      }
      else if(word == "$var") {
	parseVar(currScope);
      }
      else {
	assert(false, _file.errorString);
      }
    }
  }
  
  void parseDeclarations() {
    string word;
    while((word = _file.nextWord()) !is null) {
      if(word == "$comment") {
	assert(_comment is null);
	parseDeclarationComment();
      }
      else if(word == "$date") {
	assert(_date is null);
	parseDate();
      }
      else if(word == "$enddefinitions") {
	word = _file.nextWord();
	if(word != "$end") {
	  assert(false, _file.errorString);
	}
	else {
	  return;
	}
      }
      else if(word == "$scope") {
	assert(_root is null);
	_root = new VcdScope(null, this); // root has null parent
	parseScope(_root);
      }
      else if(word == "$timescale") {
	assert(_timeScale.isZero());
	parseTimeScale();
      }
      else if(word == "$version") {
	assert(_version is null);
	parseVersion();
      }
      else {
	assert(false, _file.errorString);
      }
    }
  }

  void parseSimulationComment() {
    string word;
    string comment;
    while((word = _file.nextWord()) != "$end") {
      comment ~= word;
      comment ~= " ";
    }
    _comments.addStringValChange(cast(uint) (_timeStamps.length-1), comment[0..$-1]);
  }

  void parseValChange(string word) {
    if(word[0] == '0' || word[0] == '1' ||
       word[0] == 'x' || word[0] == 'X' ||
       word[0] == 'z' || word[0] == 'Z') { // scalar value
      string id = word[1..$];
      auto wave = id in _lookup;
      (*wave).addScalarValChange(cast(uint) (_timeStamps.length-1), word[0]);
      if(id is null) {
	assert(false, _file.errorString());
      }
    }
    else if(word[0] == 'b' || word[0] == 'B') { // vector value
      string id = _file.nextWord();
      auto wave = id in _lookup;
      if(wave is null) {
	assert(false, _file.errorString());
      }
      if((*wave)._size < MaxVectorSize) {
	(*wave).addVectorValChange(cast(uint) (_timeStamps.length-1), word);
      }
      else {
	(*wave).addLogicStringValChange(cast(uint) (_timeStamps.length-1), word);
      }
    }
    else if(word[0] == 'r' || word[0] == 'R') {	// vector real
      string id = _file.nextWord();
      auto wave = id in _lookup;
      (*wave).addRealValChange(cast(uint) (_timeStamps.length-1), word);
      if(id is null) {
	assert(false, _file.errorString());
      }
    }
  }
  
  void parseSimulationCommand(SIM_COMMAND command) {
    _commands.addCommandValChange(cast(uint) (_timeStamps.length-1), command);
    switch(command) {
    case SIM_COMMAND.DUMPON:
      _dumpon.addScalarValChange(cast(uint) (_timeStamps.length-1), true);
      break;
    case SIM_COMMAND.DUMPOFF:
      _dumpoff.addScalarValChange(cast(uint) (_timeStamps.length-1), true);
      break;
    case SIM_COMMAND.DUMPALL:
      _dumpall.addScalarValChange(cast(uint) (_timeStamps.length-1), true);
      break;
    case SIM_COMMAND.DUMPVARS:
      _dumpvars.addScalarValChange(cast(uint) (_timeStamps.length-1), true);
      break;
    default: break;
    }
    string word;
    while((word = _file.nextWord()) != "$end") {
      parseValChange(word);
    }
  }

  void parseSimulation() {
    string word;
    SIM_COMMAND *cmd;
    while((word = _file.getNextWord()) != null) {
      if(word == "$comment") {
	parseSimulationComment();
      }
      else if(word[0] == '#') {	// timestamp
	string timeStr = word[1..$];
	if(! isNumeric(timeStr)) {
	  assert(false, _file.errorString);
	}
	else {
	  _timeStamps ~= timeStr.to!ulong;
	}
      }
      else if((cmd = word in _commandTypeLookup) !is null) {
	parseSimulationCommand(*cmd);
      }
      else {
	parseValChange(word);
      }
    }
  }
}

class VcdFile
{
  import std.stdio;
  private this(string name) {
    _name = name;
    _file = File(name, "r");
  }
  File     _file;
  string   _name;
  char[]   _buf;
  char[][] _words;
  // index of the word to return when nextWord called
  size_t   _index = 0;
  // line number of the file
  size_t   _lnum = 0;
  string nextWord() {
    string word = getNextWord();
    if(word is null) {
      assert(false, "Unexpected EOF");
    }
    return word;
  }
  string getNextWord() {
    while(_index == _words.length) {
      import std.array;
      ++_lnum;
      if(_file.readln(_buf) == 0) {
	return null;
      }
      _words = split(_buf);
      _index = 0;
    }
    return cast(string) _words[_index++];
  }
  string errorString() {
    import std.string;
    return format("Unexpected token '%s' while parsing VCD file: " ~
		  "%s at line number %d", _words[_index-1], _name, _lnum);
  }
}
