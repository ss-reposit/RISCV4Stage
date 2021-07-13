module cpu # (
	parameter IW = 32, // instr width
	parameter REGS = 32 // number of registers
)(
	input clk,
	input reset,
	
	// read only port 1
	output [IW-1:0] o_pc_addr, //chose the addr to read/write from/to in mem
	output o_pc_rd, //specify read to port 1 
	input [IW-1:0] i_pc_rddata, //instructions read from mem
	output [3:0] o_pc_byte_en, //can read 1 byte of 2 byte at a time
	
	// read/write port 2
	output [IW-1:0] o_ldst_addr, //this addr determines bytes to read/write
	output o_ldst_rd, // determines if ld 
	output o_ldst_wr, //determines if st
	input [IW-1:0] i_ldst_rddata, //input from read
	output [IW-1:0] o_ldst_wrdata, //output from write
	output [3:0] o_ldst_byte_en, //can read 1/2 bytes, can write 1/2/4 bytes
	
	output [IW-1:0] o_tb_regs [0:REGS-1]
);
	wire pcwrite;
	wire alusrcB;
	wire [3:0] aluControl;
	wire regsrc;
	wire regwrite;
	wire memWrite;
	wire resultsrc;
	wire [3:0] byteControl;
	wire [IW-1:0] instr;
	wire BrUn;
	wire BrEq;
	wire BrLt;

data_path dp1(
			.clk(clk), 
			.reset(reset),

			.ic_pcwrite(pcwrite),
			.ic_alusrcB(alusrcB),
			.ic_aluControl(aluControl),
			.ic_regsrc(regsrc),
			.ic_regwrite(regwrite),
			.ic_memWrite(memWrite),
			.ic_resultsrc(resultsrc),
			.ic_byteControl(byteControl),

			.i_ldst_rddata(i_ldst_rddata),
			.o_ldst_wrdata(o_ldst_wrdata),
			.i_pc_rddata(i_pc_rddata),
			
			.o_pc_rd(o_pc_rd),
			.o_pc_addr(o_pc_addr),
			.o_pc_byte_en(o_pc_byte_en),
			.o_tb_regs(o_tb_regs),
			.o_ldst_rd(o_ldst_rd),
			.o_ldst_wr(o_ldst_wr),
			.o_ldst_byte_en(o_ldst_byte_en),
			.o_ldst_addr(o_ldst_addr),
			.o_instrDC(instr),
			.ic_BrUn(BrUn),
			.o_BrEq(BrEq),
			.o_BrLt(BrLt));


control_path cp1(
				.clk(clk),
				.reset(reset),
				.i_instrC(instr),
				.i_BrEq(BrEq),
				.i_BrLt(BrLt),
				
				.oc_pcwrite(pcwrite),
				.oc_alusrcB(alusrcB),
				.oc_aluControl(aluControl),
				.oc_regsrc(regsrc),
				.oc_regwrite(regwrite),
				.oc_memWrite(memWrite),
				.oc_resultsrc(resultsrc),
				.oc_byteControl(byteControl),
				.oc_BrUn(BrUn));
endmodule
	
module data_path #(parameter IW = 32, parameter REGS = 32)(
	
	input clk, 
	input reset,
	
	input ic_pcwrite,
	input ic_alusrcB,
	input [3:0] ic_aluControl,
	input ic_regsrc,
	input ic_regwrite,
	input ic_memWrite,
	input ic_resultsrc,
	input [3:0] ic_byteControl,
	input ic_BrUn,
	
	input [IW-1:0] i_ldst_rddata,
	output [IW-1:0] o_ldst_wrdata,
	input [IW-1:0] i_pc_rddata,
	
	output o_pc_rd,
	output [IW-1:0] o_pc_addr,
	output [3:0] o_pc_byte_en,
	output [IW-1:0] o_tb_regs [0:REGS-1],
	output o_ldst_rd,
	output o_ldst_wr,
	output [3:0] o_ldst_byte_en,
	output [IW-1:0] o_ldst_addr,
	
	output [IW-1:0] o_instrDC,
	output o_BrEq,
	output o_BrLt,
	output logic [31:0] instructionCounter  //debug  counts instructions that have completed
);
	wire [IW-1:0] instrFDW;
	wire [IW-1:0] pcFE;
	wire [IW-1:0] pcplus4FD;
	wire [IW-1:0] srcADE;
	wire [IW-1:0] srcBDE;
	wire [IW-1:0] extimmDE;
	wire [IW-1:0] aluResultEM;
	wire [IW-1:0] writeDataEM;
	wire [IW-1:0] readDataMW;
	wire [IW-1:0] aluOutMW;
	wire [IW-1:0] resultWDF;
	
	logic [1:0] count;
	logic [1:0] kcount;
	logic NcycleClock;
	logic NcycleClockShiftedk;
	logic duty75clock;
	always_ff @(posedge clk or posedge reset) begin
		if(reset) begin
			count <= 2'b01;
			NcycleClock <= '0;
		end else begin
			if(count == 2'b01) begin
				count <= 2'b00;
				NcycleClock <= ~NcycleClock;
            end else
				count <= count + 2'b01;
       end
	end
	
	always_ff @(posedge clk or posedge reset) begin
		if(reset) begin
			kcount <= 2'b00;
			NcycleClockShiftedk <='0;
		end else begin
			if(^kcount) begin 
				NcycleClockShiftedk <= 1'b1;
				kcount <= kcount + 2'b01;
			end
			else begin
				NcycleClockShiftedk <= 1'b0;
				kcount <= kcount + 2'b01;
			end
		end
	end
	
	assign duty75clock = NcycleClock | NcycleClockShiftedk;
	
	logic resetext;
	logic resetextext;
	regpc #(.IW(1))  rpc2(.clk(clk), .reset(1'b0), .D(reset), .Q(resetext));
	regpc #(.IW(1))  rpc3(.clk(clk), .reset(1'b0), .D(resetext), .Q(resetextext));
	
	
	/*******************************/
	//Debug Logic used to count the #instructions executed
	always_ff @ (posedge duty75clock or posedge reset) begin
		if(reset)
			instructionCounter <= 32'hFFFFFFFF; //counts at end of instruction
		else
			instructionCounter <= instructionCounter + 32'd1;
	end
	/******************************/
	
	fetch f1(.clk(duty75clock), .reset(reset), .resetext(resetextext), .i_resultF(resultWDF), .o_pcF(pcFE), .o_instrF(instrFDW), .i_pc_rddata(i_pc_rddata),
				.o_pc_rd(o_pc_rd), .o_pc_addr(o_pc_addr), .o_pc_byte_en(o_pc_byte_en), .ic_pcwrite(ic_pcwrite), .ic_byteControl(ic_byteControl), .o_pcplus4F(pcplus4FD));
	
	decode d1(.clk(clk), .clkduty75(duty75clock), .reset(reset), .i_instrD(instrFDW), .i_resultD(resultWDF), .o_extimmD(extimmDE),
					.o_srcAD(srcADE), .o_srcBD(srcBDE), .ic_regwrite(ic_regwrite),
					.o_tb_regs(o_tb_regs), .i_pcplus4D(pcplus4FD));
	
	execute e1(.i_extimmE(extimmDE), .i_srcAE(srcADE), .i_srcBE(srcBDE), .o_aluResultE(aluResultEM), .o_writeDataE(writeDataEM), .i_pcE(pcFE), .ic_regsrc(ic_regsrc),
				.ic_alusrcB(ic_alusrcB), .ic_aluControl(ic_aluControl), .ic_BrUn(ic_BrUn), .o_BrEq(o_BrEq), .o_BrLt(o_BrLt));
	
	memory me1(.i_writeDataM(writeDataEM), .i_aluResultM(aluResultEM), .o_aluOutM(aluOutMW), .o_readDataM(readDataMW), 
				.ic_memWrite(ic_memWrite), .ic_byteControl(ic_byteControl), .o_ldst_rd(o_ldst_rd), .o_ldst_wr(o_ldst_wr), .o_ldst_byte_en(o_ldst_byte_en),
				.o_ldst_addr(o_ldst_addr), .i_ldst_rddata(i_ldst_rddata), .o_ldst_wrdata(o_ldst_wrdata));
	
	writeback wb1(.i_readDataW(readDataMW), .i_aluOutW(aluOutMW), .o_resultW(resultWDF), .ic_resultsrc(ic_resultsrc), .i_instrW(instrFDW));
	
	assign o_instrDC = instrFDW;
endmodule

module control_path #( parameter IW = 32)(
	
	input clk,
	input reset,
	input [IW-1:0] i_instrC,
	input i_BrEq,
	input i_BrLt,
	
	output logic oc_pcwrite,
	output logic oc_alusrcB,
	output logic [3:0] oc_aluControl,
	output logic oc_regsrc,
	output logic oc_regwrite,
	output logic oc_memWrite,
	output logic oc_resultsrc,
	output logic [3:0] oc_byteControl,
	output logic oc_BrUn
); 
	//USE lookup table (Combinational ROM) to generate control signals
	//need 9 bits to uniquely identify all instructions, 
	//all Branch instructions have 2 outcomes, 
	//use the branch inputs to determine which one
	
	//11 bit input, 15 bit output
	wire [10:0] uniqueID;
	
	localparam
		ADD= 	'b000001100??,
		SUB= 	'b100001100??,
		XOR= 	'b010001100??,
		OR=  	'b011001100??,
		AND= 	'b011101100??,
		LSL= 	'b000101100??,
		LSR= 	'b010101100??,
		ASR= 	'b110101100??,
		SLT= 	'b001001100??,
		SLTU=	'b001101100??,
		
		ADDI=	'b?00000100??,
		XORI= 	'b?10000100??,
		ORI=  	'b?11000100??,
		ANDI= 	'b?11100100??,
		LSLI= 	'b000100100??,
		LSRI= 	'b010100100??,
		ASRI= 	'b110100100??, 
		SLTI= 	'b?01000100??,
		SLTUI=	'b?01100100??,
		
		LB=		'b?00000000??, //if instruction all zeros, this selected this is possible case but it shouldn't be selected if the whole instruction is zero
		LH=		'b?00100000??,
		LW=		'b?01000000??,
		LBU=	'b?10000000??,
		LHU=	'b?10100000??,
		
		SB=		'b?00001000??,
		SH=		'b?00101000??,
		SW=		'b?01001000??,
		
		LUI=	'b????01101??,
		AUIPC=	'b????00101??,
		
		BEQF=	'b?000110000?,
		BNEF=	'b?001110001?,
		BLTF=	'b?10011000?0,
		BGEF=	'b?10111000?1,
		BLTUF=	'b?11011000?0,
		BGEUF=	'b?11111000?1,
		
		BEQT=	'b?000110001?,
		BNET=	'b?001110000?,
		BLTT=	'b?10011000?1,
		BGET=	'b?10111000?0,
		BLTUT=	'b?11011000?1,
		BGEUT=	'b?11111000?0,
		
		JAL=	'b????11011??,
		JALR=	'b?00011001??;
	
	localparam
		PC4= 	1'b0,
		PCALU=	1'b1,
		BYTE= 	4'b0001,
		HALF=	4'b0011,
		WORD=	4'b1111,
		RREAD=	1'b0,
		RWRITE=	1'b1,
		SSA=	1'b0,
		SSPC=	1'b1,
		SSB=	1'b0,
		SSI=	1'b1,
		AADD= 	4'd0,
        ASUB=   4'd1,
        AXOR=   4'd2,
        AOR=    4'd3,
        AAND=   4'd4,
        ALSL=   4'd5,
        ALSR=   4'd6,
        AASR=   4'd7,
        ASLT=   4'd8,
        ASLTU=  4'd9,
		ALUI=	4'd10,
		AAUIPC=	4'd11,
		BRS=	1'b0,
		BRU=	1'b1,
		MREAD=	1'b0,
		MWRITE=	1'b1,
		RSREAD=	1'b1,
		RSALU=	1'b0;


		
	always_comb begin
		casez(uniqueID)
			ADD:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, AADD, BRS, MREAD, RSALU};
			SUB:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, ASUB, BRS, MREAD, RSALU};
			XOR:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, AXOR, BRS, MREAD, RSALU};
			OR: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, AOR, BRS, MREAD, RSALU};
			AND: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, AAND, BRS, MREAD, RSALU};
			LSL: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, ALSL, BRS, MREAD, RSALU};
			LSR: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, ALSR, BRS, MREAD, RSALU};
			ASR: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, AASR, BRS, MREAD, RSALU};
			SLT: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, ASLT, BRS, MREAD, RSALU};
			SLTU: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSB, ASLTU, BRS, MREAD, RSALU};
			
			ADDI:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSALU};
			XORI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AXOR, BRS, MREAD, RSALU};
			ORI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AOR, BRS, MREAD, RSALU};	
			ANDI:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AAND, BRS, MREAD, RSALU}; 
			LSLI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, ALSL, BRS, MREAD, RSALU};
			LSRI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, ALSR, BRS, MREAD, RSALU};
			ASRI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AASR, BRS, MREAD, RSALU};
			SLTI: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, ASLT, BRS, MREAD, RSALU};
			SLTUI:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, ASLTU, BRS, MREAD, RSALU};

			LB:	begin	
				if(|i_instrC) //only if whole instruction isn't zero
					{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, BYTE, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSREAD};
				else
					{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = '0;
			end
			LH:		{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, HALF, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSREAD};
			LW:		{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSREAD};
			LBU:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, BYTE, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSREAD};
			LHU:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, HALF, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSREAD};

			SB:		{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, BYTE, RREAD, SSA, SSI, AADD, BRS, MWRITE, RSALU};
			SH:		{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, HALF, RREAD, SSA, SSI, AADD, BRS, MWRITE, RSALU};
			SW:		{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSA, SSI, AADD, BRS, MWRITE, RSALU};

			LUI:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSA, SSI, ALUI, BRS, MREAD, RSALU};
			AUIPC:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RWRITE, SSPC, SSI, AAUIPC, BRS, MREAD, RSALU};
			
			BEQF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BNEF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BLTF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BGEF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BLTUF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRU, MREAD, RSALU};
			BGEUF:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PC4, WORD, RREAD, SSPC, SSI, AADD, BRU, MREAD, RSALU};
			
			BEQT:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BNET:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BLTT:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BGET:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			BLTUT:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRU, MREAD, RSALU};
			BGEUT:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RREAD, SSPC, SSI, AADD, BRU, MREAD, RSALU};
			
			JAL: 	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RWRITE, SSPC, SSI, AADD, BRS, MREAD, RSALU};
			JALR:	{oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = {PCALU, WORD, RWRITE, SSA, SSI, AADD, BRS, MREAD, RSALU};
			default: {oc_pcwrite, oc_byteControl, oc_regwrite, oc_regsrc, oc_alusrcB, oc_aluControl, oc_BrUn, oc_memWrite, oc_resultsrc} = '0;
		endcase
	end
	
	assign uniqueID = {i_instrC[30], i_instrC[14:12], i_instrC[6:2], i_BrEq, i_BrLt};
endmodule

module fetch #( parameter IW = 32)(
	input clk,
	input reset,
	input resetext,
	
	input [IW-1:0] i_resultF,
	output [IW-1:0] o_pcF,
	output [IW-1:0] o_pcplus4F,
	output [IW-1:0] o_instrF,
	
	input [IW-1:0] i_pc_rddata,
	output o_pc_rd,
	output [IW-1:0] o_pc_addr,
	output [3:0] o_pc_byte_en,
	
	input ic_pcwrite,
	input [3:0] ic_byteControl
);
	wire [IW-1:0] muxedPc; 
	wire [IW-1:0] muxedmuxedPc; 
	wire [IW-1:0] pcF;
	wire [IW-1:0] pcplus4F;
	
	mux2to1 m5 (.A(32'b0), .B(muxedPc), .sel(resetext), .out(muxedmuxedPc));
	
	mux2to1 m1(.A(i_resultF), .B(pcplus4F), .sel(ic_pcwrite), .out(muxedPc));
	regpc rpc1(.clk(clk), .reset(reset), .D(muxedmuxedPc), .Q(pcF));
	addsub4 a41(.pc(pcF), .addsub(1'b0), .pcplusmin4(pcplus4F)); 
	
	//set signals for memory interaction
	//pcF available on clock edge
	//1 cycle memory read latency
	
	assign o_pc_byte_en = 4'b1111;  //always fetch word for instructions
	
	assign o_pc_rd = clk;
	
	assign o_pc_addr = pcF; 
		
	assign o_instrF = i_pc_rddata;
	assign o_pcF = pcF; //going to send pc, not pc+4 to decode
	assign o_pcplus4F = pcplus4F;
endmodule

module decode #( parameter IW = 32, parameter REGS = 32)(
	input clk, 
	input clkduty75,
	input reset,
	
	input [IW-1:0] i_instrD,
	input [IW-1:0] i_resultD,
	output [IW-1:0] o_extimmD,
	output [IW-1:0] o_srcAD,
	output [IW-1:0] o_srcBD,
	
	input ic_regwrite,
	input [IW-1:0] i_pcplus4D,
	
	output [IW-1:0] o_tb_regs [0:REGS-1]
);
	wire [IW-1:0] muxedWriteData;
	wire writeType; 
	//if garbage ok because no writes possible without regWrite
	
	jalPath jp1(.instr(i_instrD), .writepcp4(writeType));
	mux2to1 m4 (.A(i_pcplus4D), .B(i_resultD), .sel(writeType), .out(muxedWriteData));
	
	regfile rf1(.clk(clk), .clkduty75(clkduty75), .reset(reset), .rs1(i_instrD[19:15]), .rs2(i_instrD[24:20]), .rd1(o_srcAD), .rd2(o_srcBD),
				.regWrite(ic_regwrite), .writeData(muxedWriteData), .writeAddr(i_instrD[11:7]), .tb_regfile(o_tb_regs));
	
	immExtend imE1(.instr(i_instrD), .extimm(o_extimmD));	
endmodule

module execute #( parameter IW = 32)(
	input [IW-1:0] i_extimmE,
	input [IW-1:0] i_srcAE,
	input [IW-1:0] i_srcBE,
	output [IW-1:0] o_aluResultE,
	output [IW-1:0] o_writeDataE,
	//output o_aluFlags, not gona do flags
	
	input [IW-1:0] i_pcE,
	input ic_alusrcB,
	input ic_regsrc,
	input [3:0] ic_aluControl,
	
	input ic_BrUn,
	output o_BrLt,
	output o_BrEq
);
	wire [IW-1:0] muxedSrcB;
	wire [IW-1:0] muxedSrcA;
	
	alu alu1(.aluControl(ic_aluControl), .opA(muxedSrcA), .opB(muxedSrcB), .aluResult(o_aluResultE)); 
	
	
	mux2to1 m2(.A(i_extimmE), .B(i_srcBE), .sel(ic_alusrcB), .out(muxedSrcB));
	mux2to1 m3(.A(i_pcE), .B(i_srcAE), .sel(ic_regsrc), .out(muxedSrcA));
	assign o_writeDataE = i_srcBE;
	
	branchComparator b1(.A(i_srcAE), .B(i_srcBE), .BrUn(ic_BrUn), .BrEq(o_BrEq), .BrLt(o_BrLt)); 
endmodule

module memory #( parameter IW = 32)(
	input [IW-1:0] i_writeDataM,
	input [IW-1:0] i_aluResultM,
	output [IW-1:0] o_aluOutM,
	output [IW-1:0] o_readDataM,
	
	input ic_memWrite,
	input [3:0] ic_byteControl,
	
	output o_ldst_rd,
	output o_ldst_wr,
	output [3:0] o_ldst_byte_en,
	output [IW-1:0] o_ldst_addr, 
	input [IW-1:0] i_ldst_rddata,
	output [IW-1:0] o_ldst_wrdata
);
	assign o_ldst_wrdata = i_writeDataM;
	assign o_ldst_addr = i_aluResultM;
	assign o_ldst_byte_en = ic_byteControl;
	
	assign o_ldst_wr = ic_memWrite;
	assign o_ldst_rd = !ic_memWrite; //default is read 
	
	assign o_aluOutM = i_aluResultM;
	assign o_readDataM = i_ldst_rddata;
endmodule

module writeback #( parameter IW = 32)(
	input [IW-1:0] i_readDataW,
	input [IW-1:0] i_aluOutW,
	input [IW-1:0] i_instrW,
	output [IW-1:0] o_resultW,
	
	input ic_resultsrc
);
	wire [IW-1:0] extendedRead;
	
	loadExtend le1(.readData(i_readDataW), .instr(i_instrW), .extRead(extendedRead));
	mux2to1 m3(.A(extendedRead), .B(i_aluOutW), .sel(ic_resultsrc), .out(o_resultW));
endmodule

module mux2to1 #( parameter IW = 32)(
	input [IW-1:0] A,
	input [IW-1:0] B,
	input sel,
	output [IW-1:0] out
);
	assign out = sel ? A : B;
endmodule

module regfile #( parameter IW = 32, parameter REGS = 32)(
	input clk,
	input clkduty75,
	input reset,
	
	input [4:0] rs1,
	input [4:0] rs2,
	output [IW-1:0] rd1,
	output [IW-1:0] rd2,
	input regWrite,
	input [IW-1:0] writeData,
	input [4:0] writeAddr,

	output [IW-1:0] tb_regfile [0:REGS-1]
);
	
	logic [IW-1:0] regfile32x32 [0:REGS-1];
	
	
	always_ff @(posedge clk or posedge reset) begin
		if(reset) begin
			regfile32x32[0 ] <= '0;
			regfile32x32[1 ] <= '0;
			regfile32x32[2 ] <= '0;
			regfile32x32[3 ] <= '0;
			regfile32x32[4 ] <= '0;
			regfile32x32[5 ] <= '0;
			regfile32x32[6 ] <= '0;
			regfile32x32[7 ] <= '0;
			regfile32x32[8 ] <= '0;
			regfile32x32[9 ] <= '0;
			regfile32x32[10] <= '0;
			regfile32x32[11] <= '0;
			regfile32x32[12] <= '0;
			regfile32x32[13] <= '0;
			regfile32x32[14] <= '0;
			regfile32x32[15] <= '0;
			regfile32x32[16] <= '0;
			regfile32x32[17] <= '0;
			regfile32x32[18] <= '0;
			regfile32x32[19] <= '0;
			regfile32x32[20] <= '0;
			regfile32x32[21] <= '0;
			regfile32x32[22] <= '0;
			regfile32x32[23] <= '0;
			regfile32x32[24] <= '0;
			regfile32x32[25] <= '0;
			regfile32x32[26] <= '0;
			regfile32x32[27] <= '0;
			regfile32x32[28] <= '0;
			regfile32x32[29] <= '0;
			regfile32x32[30] <= '0;
			regfile32x32[31] <= '0;
		end else begin
			if(regWrite && ~clkduty75) begin
				if(writeAddr) //dont write to 0x
					regfile32x32[writeAddr] <= 	writeData;
			end
		end
	end
	
	assign rd1 = regfile32x32[rs1];
	assign rd2 = regfile32x32[rs2];
	assign tb_regfile = regfile32x32;
endmodule

module alu #( parameter IW = 32)(
	input [3:0] aluControl,
	input signed [IW-1:0] opA,
	input signed [IW-1:0] opB,
	
	output logic  signed [IW-1:0] aluResult
	//currently no alu flags
);
	localparam
		ADD = 4'd0,
		SUB = 4'd1,
		XOR = 4'd2,
		OR = 4'd3,
		AND = 4'd4,
		LSL = 4'd5,
		LSR = 4'd6,
		ASR = 4'd7,
		SLT = 4'd8,
		SLTU = 4'd9,
		LUI = 4'd10,
		AUIPC = 4'd11;
		
	always_comb begin
		case(aluControl)
			ADD:
				aluResult <= opA + opB;
			SUB:
				aluResult <= opA - opB;
			XOR:
				aluResult <= opA ^ opB;
			OR:
				aluResult <= opA | opB;
			AND:
				aluResult <= opA & opB;
			LSL:
				aluResult <= opA << opB[4:0];
			LSR:
				aluResult <= opA >> opB[4:0];
			ASR:
				aluResult <= opA >>> opB[4:0];
			SLT:
				aluResult <= (opA < opB) ? 32'd1: 32'd0;
			SLTU:
				aluResult <= ($unsigned(opA) < $unsigned(opB)) ? 32'd1: 32'd0;
			LUI:
				aluResult <= opB; //opB immediate in upper bits 
			AUIPC:
				aluResult <= opA + (opB);//opB immediate in upper bits 
			default: aluResult <= 'x;
		endcase
	end
endmodule

module addsub4 #( parameter IW = 32)(
	input [IW-1:0] pc,
	input addsub,
	output [IW-1:0] pcplusmin4
);	
	assign pcplusmin4 =  addsub ? pc - 4: pc + 4; 
endmodule

module immExtend  #( parameter IW = 32)( //sign bit always bit 31 for all immediates
	input [IW-1:0] instr,
	output logic [IW-1:0] extimm
);
	parameter
		R = ('b01100),
		I = ('b00100),
		I_1=('b00000), //I type loads
		S = ('b01000),
		B = ('b11000),
		U = ('b01101),
		U_1=('b00101), //for AUIPC
		J = ('b11011),
		J_1=('b11001); //jalr
	
	always_comb begin
		case(instr[6:2])
			R:
				extimm <= '0;
			I: 
				extimm <= {{21{instr[31]}}, instr[30:20]};
			I_1: 
				extimm <= {{21{instr[31]}}, instr[30:20]};
			S:
				extimm <= {{21{instr[31]}}, instr[30:25], instr[11:8], instr[7]};
			B:
				extimm <= {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
			U:
				extimm <= {instr[31], instr[30:20], instr[19:12], 12'b0};
			U_1:
				extimm <= {instr[31], instr[30:20], instr[19:12], 12'b0};
			J:
				extimm <= {{12{instr[31]}}, instr[19:12], instr[20], instr[30:25], instr[24:21], 1'b0};
			J_1:
				extimm <= {{21{instr[31]}}, instr[30:20]};
			default: extimm <= 'x;
		endcase
	end
endmodule

module loadExtend #(parameter IW = 32)(
	input [IW-1:0] readData,
	input [IW-1:0] instr,
	output logic [IW-1:0] extRead
);
	wire [2:0] loadType;
	
	localparam
		LB=		'b000,  //funct3 values used to sign/unsign extend
		LH=		'b001,
		LW=		'b010,
		LBU=	'b100,
		LHU=	'b101;
		
	always_comb begin
		case(loadType)
			LB:
				extRead = {{25{readData[7]}}, readData[6:0]};
			LH:	
				extRead = {{17{readData[15]}}, readData[14:0]};
			LW:	
				extRead = readData;
			LBU:
				extRead = {{24{1'b0}}, readData[7:0]};
			LHU:
				extRead = {{16{1'b0}}, readData[15:0]};
			default: extRead = 'x;
		endcase
	end	
	
	assign loadType = instr[14:12];
endmodule
module regpc #( parameter IW = 32)(
	input clk,
	input reset,
	
	input [IW-1:0] D,
	output logic [IW-1:0] Q
);
	
	always_ff @(posedge clk or posedge reset) begin
		if(reset)
			Q <= '0;
		else
			Q <= D;
	end		
endmodule

module branchComparator #( parameter IW = 32)(
	input signed [IW-1:0] A,
	input signed [IW-1:0] B,
	input BrUn,
	
	output logic BrEq,
	output logic BrLt
);

	always_comb begin
		case(BrUn)
			1'b0: begin
				BrEq = (A == B) ? '1 : '0; 
				BrLt = (A < B) ? '1 : '0;
			end
			
			1'b1: begin
				BrEq = ($unsigned(A) == $unsigned(B)) ? '1 : '0; 
				BrLt = ($unsigned(A) < $unsigned(B)) ? '1 : '0;
			end
			
			default: begin
				BrEq = 'x;
				BrLt = 'x;
			end
		endcase
	end
endmodule

module jalPath #( parameter IW = 32)(
	input [IW-1:0] instr,
	output logic writepcp4
);
	always_comb begin
		case(instr[6:2])
			5'b11011: writepcp4 = '1; //JAL
			5'b11001: writepcp4 = '1; //JALR
			default: writepcp4 = '0; //else write from ALU
		endcase
	end
endmodule
