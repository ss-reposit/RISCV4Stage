module cpu # (
	parameter IW = 32, // instr width
	parameter REGS = 32 // number of registers
)(
	input clk,
	input reset,
	
	// read only port 1
	output [IW-1:0] o_pc_addr, 
	output o_pc_rd, 
	input [IW-1:0] i_pc_rddata, 
	output [3:0] o_pc_byte_en, 
	
	// read/write port 2
	output [IW-1:0] o_ldst_addr, 
	output o_ldst_rd, 
	output o_ldst_wr, 
	input [IW-1:0] i_ldst_rddata, 
	output [IW-1:0] o_ldst_wrdata, 
	output [3:0] o_ldst_byte_en, 
	
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

module data_path #(parameter IW = 32, parameter REGS = 32) (
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
	output o_BrLt
);
	wire [IW-1:0] instrF;
	wire [IW-1:0] instrD;
	wire [IW-1:0] instrXM;
	wire [IW-1:0] instrW;
	wire [IW-1:0] pcF;
	wire [IW-1:0] pcD;
	wire [IW-1:0] pcXM;
	wire [IW-1:0] pcW;
	wire [IW-1:0] srcAD;
	wire [IW-1:0] srcAXM;
	wire [IW-1:0] srcBD;
	wire [IW-1:0] srcBXM;
	wire [IW-1:0] readDataM;
	wire [IW-1:0] readDataW;
	wire [IW-1:0] aluOutM;
	wire [IW-1:0] aluOutW;
	wire [IW-1:0] resultXMF;
	//logic [IW-1:0] resultDF;
	wire [IW-1:0] resultWD;
	wire [IW-1:0] extimmD;
	wire [IW-1:0] extimmXM;
	
	//control singals pipelined
	wire [IW-1:0] IC_XM;
	wire [IW-1:0] IC_W;
	//wire ic_pcwriteXM;
	wire ic_regwriteW;
	wire bc_BrEq;
	wire bc_BrLt;
	
	wire [4:0] writeAddrW; //generate in W, from instruction
	wire [31:0] pcAligned; //pcf - 4 so that the pc in the reg is correct
	
	//forwarding signals
	wire [1:0] forwardAmuxsel1;
	wire [1:0] forwardBmuxsel2;
	wire forwardADDr;
	wire forwardData;
	
	wire [31:0] forwardedA;
	wire [31:0] forwardedB;
	wire [31:0] forwardedAddr;
	wire [31:0] forwardedData;
	
	//stall signals, no stalls needed in this pipeline b/c forwarding fixes all
	wire stallF = 1'b1; //stall low
	wire stallD = 1'b1;
	wire noStall = 1'b1;
	//flush signals (needed for branch takesn/jals)
	logic flushFD; 
	logic flushXM;
	
	 
	stage1 F(
		.clk(clk),
		.reset(reset),
		.enable(stallF), 
		.i_resultF(resultXMF), 
		.o_pcF(pcF),
		.o_instrF(instrF),
		.i_pc_rddata(i_pc_rddata),
		.o_pc_rd(o_pc_rd),
		.o_pc_addr(o_pc_addr),
		.o_pc_byte_en(o_pc_byte_en),
		.ic_pcwrite(ic_pcwriteXM));
	
	
	regpc D_FD(.clk(clk), .reset(reset), .clr(flushFD), .enable(stallD), .D(instrF), .Q(instrD)); //here need 2 cycle flush
	
	regpc C_FD1(.clk(clk), .reset(reset), .clr(ic_pcwriteXM), .enable(stallD), .D(pcF), .Q(pcAligned)); //use ic_pcwriteXM b/c only 1 cycle (branch taken flush)
	
	regpc C_FD2(.clk(clk), .reset(reset), .clr(ic_pcwriteXM), .enable(stallD), .D(pcAligned), .Q(pcD));
	
	
	stage2 D(
		.clk(clk), 
		.reset(reset),
		.i_instrD(instrD),
		.i_resultD(resultWD),
		.o_srcAD(srcAD),
		.o_srcBD(srcBD),
		.ic_regwrite(ic_regwriteW),
		.i_RFwriteAddr(writeAddrW),
		.o_tb_regs(o_tb_regs));
	

	forwardingMux fm1(
		.A(srcAD), //default
		.B(aluOutM), //MX //need to use regged value to prevent infinite loop
		.C(resultWD), //W
		.sel(forwardAmuxsel1),
		.out(forwardedA));
			
	forwardingMux fm2(
		.A(srcBD), //default
		.B(aluOutM), //MX
		.C(resultWD), //W
		.sel(forwardBmuxsel2),
		.out(forwardedB));	
	
	immExtend im1(.instr(instrD), .extimm(extimmD));
	
	
	regpc EXT_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D(extimmD), .Q(extimmXM));
	
	regpc D_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D(instrD), .Q(instrXM));
	regpc C_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D(pcD), .Q(pcXM));
	regpc A_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D(forwardedA), .Q(srcAXM));
	regpc B_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D(forwardedB), .Q(srcBXM));
	regpc IC_DXM(.clk(clk), .reset(reset), .clr(flushXM), .enable(noStall), .D({17'd0, ic_aluControl, ic_byteControl, ic_regwrite, ic_regsrc, ic_alusrcB, ic_pcwrite, ic_BrUn, ic_memWrite, ic_resultsrc}), .Q(IC_XM));
	
	mux2to1 WXMfm1(.A(resultWD), .B(srcAXM), .sel(forwardADDr), .out(forwardedAddr));
	mux2to1 WXMfm2(.A(resultWD), .B(srcBXM), .sel(forwardData), .out(forwardedData));
	
	branchComparator b1(.A(forwardedAddr), .B(forwardedData), .BrUn(IC_XM[2]), .BrEq(bc_BrEq), .BrLt(bc_BrLt));
	
	stage3 XM(
		.i_instrE(instrXM),
		.i_extimmE(extimmXM),
		.i_srcAE(forwardedAddr),
		.i_srcBE(forwardedData),
		.i_pcE(pcXM),
		.ic_alusrcB(IC_XM[4]),
		.ic_regsrc(IC_XM[5]),
		.ic_aluControl(IC_XM[14:11]),
		//.ic_BrUn(IC_XM[2]), 
		//.o_BrEq(bc_BrEq), 
		//.o_BrLt(bc_BrLt),
		.o_aluOutM(aluOutM),
		.o_readDataM(readDataM),
		.ic_memWrite(IC_XM[1]),
		.ic_byteControl(IC_XM[10:7]),
		.o_ldst_rd(o_ldst_rd),
		.o_ldst_wr(o_ldst_wr),
		.o_ldst_byte_en(o_ldst_byte_en),
		.o_ldst_addr(o_ldst_addr), 
		.i_ldst_rddata(i_ldst_rddata),
		.o_ldst_wrdata(o_ldst_wrdata));
	
	branchController bctl1(.instr(instrXM), .i_BrEq(bc_BrEq), .i_BrLt(bc_BrLt), .o_branchTaken(ic_pcwriteXM));
	
	regpc D_XMW(.clk(clk), .reset(reset), .clr(1'b0), .enable(noStall), .D(instrXM), .Q(instrW));	
	regpc C_XMW(.clk(clk), .reset(reset), .clr(1'b0), .enable(noStall), .D(pcXM), .Q(pcW));	
	regpc IC_XMW(.clk(clk), .reset(reset), .clr(1'b0), .enable(noStall), .D(IC_XM), .Q(IC_W));
	regpc ALU_XMW(.clk(clk), .reset(reset), .clr(1'b0), .enable(noStall), .D(aluOutM), .Q(aluOutW));
	//not going to add pipeline reg for this because it already has 1 cycle delay
	//regpc LD_XMW(.clk(clk), .reset(reset), .enable(noStall), .D(readDataM), .Q(readDataW));
	
	stage4 W(
		.i_readDataW(readDataM),
		.i_aluOutW(aluOutW),
		.i_instrW(instrW),
		.i_pcW(pcW),
		.ic_resultsrc(IC_W[0]),
		.o_resultW(resultWD));
	
	
	forwardingUnit fu1(
		.instrD(instrD),
		.instrXM(instrXM),
		.instrW(instrW),
		.regWriteXM(IC_XM[6]),
		.regWriteW(IC_W[6]),
		.forwardA(forwardAmuxsel1),
		.forwardB(forwardBmuxsel2),
		.forwardADDr(forwardADDr),
		.forwardData(forwardData));
		
	hazardUnit hu1(
		.clk(clk),
		.branchTaken(ic_pcwriteXM),
		.flushFD(flushFD),
		.flushXM(flushXM)); 
	
	assign ic_regwriteW = IC_W[6]; //propogates
	assign writeAddrW = instrW[11:7]; //doesnt matter if garbage
	assign o_instrDC = instrD;
	assign resultXMF = aluOutM;
	assign o_BrEq = 1'b0; //for now, could remove later as no longer needed
	assign o_BrLt = 1'b0;
endmodule

module control_path #(parameter IW = 32)(
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

module stage1 #( parameter IW = 32)(
	input clk,
	input reset,
	input enable,
	
	input [IW-1:0] i_resultF,
	output [IW-1:0] o_pcF,
	output [IW-1:0] o_instrF,
	
	input [IW-1:0] i_pc_rddata,
	output o_pc_rd,
	output [IW-1:0] o_pc_addr,
	output [3:0] o_pc_byte_en,
	
	input ic_pcwrite
);
	
	wire [IW-1:0] muxedPc; 
	wire [IW-1:0] pcF;
	wire [IW-1:0] pcplus4F;
	
	mux2to1 m1(.A(i_resultF), .B(pcplus4F), .sel(ic_pcwrite), .out(muxedPc));
	regpc rpc1(.clk(clk), .enable(enable),  .clr(1'b0), .reset(reset), .D(muxedPc), .Q(pcF));
	addsub4 a41(.pc(pcF), .addsub(1'b0), .pcplusmin4(pcplus4F)); 
	
	//set signals for memory interaction
	//pcF available on clock edge
	//1 cycle memory read latency

	assign o_pc_byte_en = 4'b1111;  //always fetch word for instructions
	assign o_pc_rd = 1'b1 & (~reset); //don't fetch while reset high
	assign o_pc_addr = pcF; 	
	assign o_instrF = i_pc_rddata;
	assign o_pcF = pcF; //going to send pc, not pc+4 to decode
endmodule

module stage2 #( parameter IW = 32, parameter REGS = 32)(
	input clk, 
	input reset,
	
	input [IW-1:0] i_instrD,
	input [IW-1:0] i_resultD,
	output [IW-1:0] o_srcAD,
	output [IW-1:0] o_srcBD,
	
	input ic_regwrite,
	input [4:0] i_RFwriteAddr,
	
	output [IW-1:0] o_tb_regs [0:REGS-1]
);
	//if garbage ok because no writes possible without regWrite
	//rs1 or rs2 may be garbage
	
	regfile rf1(.clk(clk), .reset(reset), .rs1(i_instrD[19:15]), .rs2(i_instrD[24:20]), .rd1(o_srcAD), .rd2(o_srcBD),
				.regWrite(ic_regwrite), .writeData(i_resultD), .writeAddr(i_RFwriteAddr), .tb_regfile(o_tb_regs));
	//no jalpath, put instruction extended in execute
endmodule

module stage3 #( parameter IW = 32)(
	input [IW-1:0] i_instrE,
	input [IW-1:0] i_srcAE,
	input [IW-1:0] i_srcBE,
	input [31:0] i_extimmE,
	//output o_aluFlags, not gona do flags
	
	input [IW-1:0] i_pcE,
	input ic_alusrcB,
	input ic_regsrc,
	input [3:0] ic_aluControl,
	
	//memory
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
	wire [IW-1:0] muxedSrcB;
	wire [IW-1:0] muxedSrcA;
	
	//links
	wire [IW-1:0] o_writeDataE;
	wire [IW-1:0] o_aluResultE;
	wire [IW-1:0] i_writeDataM;
	wire [IW-1:0] i_aluResultM;
	
	//wire [IW-1:0] i_extimmE;
	
	wire memInstr =  (i_instrE[6:0] == 7'b0000011);
	
	alu alu1(.aluControl(ic_aluControl), .opA(muxedSrcA), .opB(muxedSrcB), .aluResult(o_aluResultE)); 
	
	mux2to1 m2(.A(i_extimmE), .B(i_srcBE), .sel(ic_alusrcB), .out(muxedSrcB));
	mux2to1 m3(.A(i_pcE), .B(i_srcAE), .sel(ic_regsrc), .out(muxedSrcA));
	
	assign o_writeDataE = i_srcBE;
	
	//link
	assign i_writeDataM = o_writeDataE;
	assign i_aluResultM = o_aluResultE;
	
	//memory now happens in execute
	assign o_ldst_wrdata = i_writeDataM;
	assign o_ldst_addr = i_aluResultM;
	assign o_ldst_byte_en = ic_byteControl;
	assign o_ldst_wr = ic_memWrite;
	assign o_ldst_rd = memInstr; //only read if load
	assign o_aluOutM = i_aluResultM;
	assign o_readDataM = i_ldst_rddata;
endmodule

module stage4 #(parameter IW = 32)(
	input [IW-1:0] i_readDataW,
	input [IW-1:0] i_aluOutW,
	input [IW-1:0] i_instrW,
	input [IW-1:0] i_pcW,
	input ic_resultsrc,
	
	output [IW-1:0] o_resultW
);

	wire [IW-1:0] extendedRead;
	wire [IW-1:0] pcplus4W; 
	wire [IW-1:0] tempResult;
	wire writepcp4;
	addsub4 a41(.pc(i_pcW), .addsub(1'b0), .pcplusmin4(pcplus4W)); 
	//determine jal type, if so write pc+4
	jalPath jp1(.instr(i_instrW), .writepcp4(writepcp4));
	
	loadExtend le1(.readData(i_readDataW), .instr(i_instrW), .extRead(extendedRead));
	mux2to1 m3(.A(extendedRead), .B(i_aluOutW), .sel(ic_resultsrc), .out(tempResult));
	
	mux2to1 m4(.A(pcplus4W), .B(tempResult), .sel(writepcp4), .out(o_resultW));
endmodule

module mux2to1 #( parameter IW = 32)(
	input [IW-1:0] A,
	input [IW-1:0] B,
	input sel,
	output [IW-1:0] out
);
	assign out = sel ? A : B;
endmodule

module addsub4 #( parameter IW = 32)(
	input [IW-1:0] pc,
	input addsub,
	output [IW-1:0] pcplusmin4
);	
	assign pcplusmin4 =  addsub ? pc - 4: pc + 4; 
endmodule

module regpc #( parameter IW = 32)(  //enable signal resetable reg
	input clk,
	input reset,
	input enable,
	input clr,
	
	input [IW-1:0] D,
	output logic [IW-1:0] Q
);
	always_ff @(posedge clk or posedge reset) begin
		if(reset)
			Q <= '0;
		else if(clr)
			Q <= '0; //synch clear for flushing
		else if(enable)
			Q <= D;
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

module regfile #( parameter IW = 32, parameter REGS = 32)(
	input clk,
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
			if(regWrite) begin
				if(writeAddr) //dont write to 0x
					regfile32x32[writeAddr] <= 	writeData;
			end
		end
	end
	
	assign rd1 = regfile32x32[rs1];
	assign rd2 = regfile32x32[rs2];
	assign tb_regfile = regfile32x32;
endmodule

module branchController( //small control logic in X stage
	input [31:0] instr,
	input i_BrEq,
	input i_BrLt,
	
	output logic o_branchTaken
);
	wire [10:0] uniqueID;
	localparam
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
	
	always_comb begin
		casez(uniqueID)
			BEQF: 	o_branchTaken = 1'b0;
			BNEF: 	o_branchTaken = 1'b0;
			BLTF: 	o_branchTaken = 1'b0;
			BGEF:	o_branchTaken = 1'b0;
			BLTUF: 	o_branchTaken = 1'b0;
			BGEUF: 	o_branchTaken = 1'b0;
			
			BEQT: 	o_branchTaken = 1'b1;
			BNET: 	o_branchTaken = 1'b1;
			BLTT: 	o_branchTaken = 1'b1;	
			BGET: 	o_branchTaken = 1'b1;	
			BLTUT:	o_branchTaken = 1'b1;
			BGEUT:	o_branchTaken = 1'b1;
			
			JAL: 	o_branchTaken = 1'b1;
			JALR:	o_branchTaken = 1'b1;
			default:o_branchTaken = 1'b0;
		endcase
	end
	
	assign uniqueID = {instr[30], instr[14:12], instr[6:2], i_BrEq, i_BrLt};	
endmodule

module forwardingMux(
	input [31:0] A, //default
	input [31:0] B, //MX
	input [31:0] C, //W
	
	input [1:0] sel,
	
	output [31:0] out
);
	
	assign out = A&{32{(sel == 2'b00)}} | B&{32{(sel == 2'b01)}} | C&{32{(sel == 2'b10)}}; 

endmodule

module forwardingUnit(
	input [31:0] instrD,
	input [31:0] instrXM,
	input [31:0] instrW,
	
	input regWriteXM,
	input regWriteW,
	
	output logic [1:0] forwardA, //0 = default, 1 = MX, 2 = WX, 3 = never
	output logic [1:0] forwardB, ////0 = default, 1 = MX, 2 = WX, 3 = never
	
	output logic forwardADDr,
	output logic forwardData
);
	logic M_RS1;
	logic M_RS2;
	logic W_RS1;
	logic W_RS2;
	logic W_MRS1;
	logic W_MRS2;
	
	//XM->D
		//if instrXM.Dest = instrD.src1 => set signal for mux 1
		//if instrXM.Dest = instrD.src2 => set signal for mux 2
	//W -> D
		//if instrW.Dest = instrD.src1 => set signal for mux 1
		//if instrW.Dest = instrD.src2 => set signal for mux 2
	//W->XM (rs1 used for addr always)
		//if instrW.Dest = instrXM.rs1 
	//W->XM (rs2 used for data always)
		//if instrW.Dest = instrXM.rs2 
	
	always_comb begin
		if(instrXM[11:7] == instrD[19:15]) //XM -> D_rs1
			M_RS1 <= 1'b1;
		else
			M_RS1 <= 1'b0;
		if(instrXM[11:7] == instrD[24:20]) //XM -> D_rs2
			M_RS2 <= 1'b1;
		else
			M_RS2 <= 1'b0;
		if(instrW[11:7] == instrD[19:15]) //W -> D_rs1
			W_RS1 <= 1'b1;
		else
			W_RS1 <= 1'b0;
		if(instrW[11:7] == instrD[24:20]) //W -> D_rs2
			W_RS2 <= 1'b1;
		else
			W_RS2 <= 1'b0;
		if(instrW[11:7] == instrXM[19:15]) //W -> XM_rs1 (addr)
			W_MRS1 <= 1'b1;
		else
			W_MRS1 <= 1'b0;	
		if(instrW[11:7] == instrXM[24:20]) //W -> XM_rs2 (data)
			W_MRS2 <= 1'b1;
		else
			W_MRS2 <= 1'b0;
	end
	
	always_comb begin //M state is most up-to-date so has priority
		if(M_RS1 & regWriteXM)
			forwardA <= 2'b01;
		else if(W_RS1 & regWriteW)
			forwardA <= 2'b10;
		else
			forwardA <= 2'b00;
		
		if(M_RS2 & regWriteXM)
			forwardB <= 2'b01;
		else if(W_RS2 & regWriteW)
			forwardB <= 2'b10;
		else
			forwardB <= 2'b00;
			
		if(W_MRS1 & regWriteW)
			forwardADDr <= 1'b1;
		else
			forwardADDr <= 1'b0;
			
		if(W_MRS2 & regWriteW)
			forwardData <= 1'b1;
		else
			forwardData <= 1'b0;
	end
endmodule

module hazardUnit(
	input clk,
	input branchTaken,
	output flushFD,
	output flushXM
);
	wire flushD_1cyclext;
	
	regpc #(.IW(1)) extNOOP(.clk(clk), .reset(1'b0), .clr(1'b0), .enable(1'b1), .D(branchTaken), .Q(flushD_1cyclext)); 
	
	assign flushFD = branchTaken | flushD_1cyclext; //2 cycle
	assign flushXM = branchTaken; //1 cycle 
endmodule
