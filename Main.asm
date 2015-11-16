;
; *** R A C E R ***
; Setup the SDSC tag, including correct chekcsum:
.sdsctag 2.0, "Racer - rebooted", ReleaseNotes, "Anders S. Jensen"
.memorymap
   defaultslot 0
   slotsize $8000
   slot 0 $0000          ; ROM
   slotsize $2000
   slot 1 $c000          ; RAM
.endme
.rombankmap
   bankstotal 1
   banksize $8000
   banks 1
.endro

; =============================================================================
; M A C R O S
; =============================================================================
.macro PrepareVram
rst $20
.endm

; =============================================================================
; C O N S T A N T S
; =============================================================================
.define    SPRITE_PALETTE_SIZE 16
.define    START_OF_SPRITE_PALETTE 16
.define    STACK_INIT_ADDRESS $dff0
.define    PAUSE_INTERRUPT_ADDRESS $0066
.define    DEATH_DELAY 100

.define    SPRITE_COLLISION_BIT 5
.define    VDP_CONTROL $bf
.define    VDP_DATA $be
.define    VDP_INTERRUPT_ADDRESS $0038
.define    ALL_VDP_REGISTERS 11
.define    VDP_WRITE_REGISTER_COMMAND $80
.define    ADDRESS_OF_FIRST_TILE $0000
.define    TILEMAP_ADDRESS $3800
.define    PALETTE_ADDRESS $c000 ; Bank 1 address.
.define    PALETTE_BANK_2 $c010 ; Bank 2 address.
.define    ONE_FULL_PALETTE 16
.define    TURN_SCREEN_OFF %10000000
.define    TURN_SCREEN_ON_TALL_SPRITES %11100010
.define    VDP_REGISTER_1 1
.define    VDP_VERTICAL_SCROLL_REGISTER 9
.define    SAT_Y_TABLE $3f00
.define    SAT_XC_TABLE $3f80
.define    PLAYER1_JOYSTICK_RIGHT 3
.define    PLAYER1_JOYSTICK_LEFT 2
.define    PLAYER1_START 4
.define    WHOLE_NAMETABLE 32*28*2
.define    VISIBLE_PART_OF_SCREEN 32*24*2

.define    BOTTOM_BORDER 193
.define    RIGHT_BORDER 156
.define    LEFT_BORDER 5
.define    MAX_CELS 2    ; Number of cels in a car's animation sequence.
.define    FLAG_UP 1
.define    FLAG_DOWN 0

; Player values
.define    PLAYER_VERTICAL_SPEED 6
.define    PLAYER_HORIZONTAL_SPEED 3
.define    PLAYER_X_START 110
.define    PLAYER_Y_START 135
.define    FIRST_PLAYER_TILE $2800
.define    PLAYER_METASPRITE_SIZE 32*32

; Enemy values
.define    ASH_X_START 76
.define    ASH_Y_START 1
.define    MAY_X_START 30
.define    MAY_Y_START 85
.define    IRIS_X_START 90
.define    IRIS_Y_START 170
.define    ENEMY_HORIZONTAL_SPEED 1
.define    ENEMY_VERTICAL_SPEED 2
.define    FIRST_ENEMY_TILE $2400
.define    ENEMY_METASPRITE_SIZE 32*32
.define    PASSIVE_ENEMY 0
.define    GOING_RIGHT 0
.define    GOING_LEFT 1
.define    ENEMY_RIGHT_BORDER 140
.define    ENEMY_LEFT_BORDER 18
.define    EASY_MODE_MASK %00000111
.define    HARD_MODE_MASK %00000011

.struct EnemyObject
   y db
   x db
   metasprite dw
   cel db
   index db
   movement db
.endst
; =============================================================================
; V A R I A B L E S
; =============================================================================
.ramsection "Game variables" slot 1
   VDPStatus db
   FrameCounter db
   Joystick1 db          ; For input from the joystick ports
   Joystick2 db          ; (via the ReadJoysticks function).
   SpriteBufferY dsb 64
   SpriteBufferXC dsb 128
   Scroll db             ; Vertical scroll register mirror.
   CollisionFlag db
   RandomSeed dw
   PlayerY db
   PlayerX db
   PlayerMetaSpriteDataPointer dw ; Pointer to metasprite data.
   PlayerCel db
   Ash INSTANCEOF EnemyObject
   May INSTANCEOF EnemyObject
   Iris INSTANCEOF EnemyObject
.ends

; =============================================================================
; L I B R A R I E S
; =============================================================================
.include "Support/stdlib.inc" ; General/supporting routines.
.include "Support/PSGlib.inc" ; sverx's psg library.

; =============================================================================
; R O M
; =============================================================================
.bank 0 slot 0
.org 0
   di
   im 1
   ld sp,STACK_INIT_ADDRESS
   jp Control
; ---------------------
.org $0020               ; rst $20: Prepare vram at address in HL.
   ld a,l                ; Refer to the PrepareVram macro.
   out (VDP_CONTROL),a
   ld a,h
   or $40
   out (VDP_CONTROL),a
   ret
; ---------------------
.org VDP_INTERRUPT_ADDRESS
   ex af,af'
   exx
   in a,VDP_CONTROL
   ld (VDPStatus),a
   exx
   ex af,af'
   ei
   ret
; ---------------------
.org PAUSE_INTERRUPT_ADDRESS
   retn
; ---------------------
.section "Control" free
Control:
   call InitializeFramework
   call LoadTitleScreen
   call TitlescreenLoop
Restart:
   call PrepareRace
   call MainLoop
   call Death
   jp Restart
.ends
; ---------------------
.section "Titlescreen" free
LoadTitleScreen:
   ld ix,TitlescreenImageData
   call LoadImage
   ei
   ret
TitlescreenLoop:
   call WaitForFrameInterrupt
   call Housekeeping
   ld a,(Joystick1)
   bit PLAYER1_START,a
   ret z
   jp TitlescreenLoop
.ends
; ---------------------
.section "Death" free
Death:
   ld b,DEATH_DELAY
 -:
   halt
   djnz -
   ld hl,Sprites_Palette
   ld b,SPRITE_PALETTE_SIZE
   ld a,START_OF_SPRITE_PALETTE
   call FadeOutScreen
   ret
 .ends
; ---------------------
.section "Initialize" free
InitializeFramework:
   call ClearRam
   call PSGInit
   ld hl,RegisterInitValues
   call LoadVDPRegisters
   ret
.ends
; ---------------------
.section "Racetrack code" free
PrepareRace:
   di
   ld a,TURN_SCREEN_OFF
   ld b,VDP_REGISTER_1
   call SetRegister
   call InitializeGeneralVariables
   call InitializeBackground
   call InitializeSprites
   call LoadSAT          ; Load the sprite attrib. table from the buffers.
   ld a,TURN_SCREEN_ON_TALL_SPRITES
   ld b,VDP_REGISTER_1
   call SetRegister
   ei
   halt                  ; Make sure yo don't die right when race restarts.
   halt
   ret
InitializeBackground:
   ld ix,RacetrackMockupData ; Load the racetrack dummy image data.
   call LoadImage
   ret
InitializeSprites:
   ld hl,PALETTE_BANK_2  ; Load the sprites palette.
   PrepareVram
   ld hl,Sprites_Palette
   ld bc,ONE_FULL_PALETTE
   call LoadVRAM
   call InitializePlayer
   call InitializeEnemies
   ret
InitializeGeneralVariables:
   xor a
   ld (CollisionFlag),a
   ld a,r
   ld (RandomSeed),a
   ret
; ---------------------
MainLoop:
   call WaitForFrameInterrupt
   call LoadSAT
   ld a,(Scroll)
   ld b,VDP_VERTICAL_SCROLL_REGISTER
   call SetRegister
   call Housekeeping
   ;call DetectCollision  ; Set CollisionFlag if two hardware sprites overlap.
   call MovePlayer
   call MoveEnemies
   call ScrollRacetrack  ; Not the actual vdp register updating - see above.
   call AnimatePlayer
   call AnimateEnemies
   call UpdateSATBuffers
   ld a,(CollisionFlag)  ; Respond to collision flag.
   cp FLAG_UP
   ret z
   jp MainLoop           ; Do it all again...
MoveEnemies:
   ld ix,Ash
   call MoveEnemy
   ld ix,May
   call MoveEnemy
   ld ix,Iris
   call MoveEnemy
   ret
ScrollRacetrack:
   ld a,(Scroll)
   sub PLAYER_VERTICAL_SPEED
   ld (Scroll),a
   ret
AnimatePlayer:
   ld ix,PlayerY
   ld bc,PlayerCelTable
   ld hl,PlayerMetaSpriteDataPointer
   call AnimateCar
   ret
AnimateCar:
   push hl               ; Save pointer to meta sprite data.
   ld a,(ix+4)           ; Get current cel.
   inc a
   cp MAX_CELS+1
   jp nz,+
   xor a                 ; Overflow - back to first cel.
+:
   ld (ix+4),a           ; Save the new cel number to ram.
   add a,a               ; Get the word-sized table element (the address).
   ld l,a
   ld h,0
   add hl,bc             ; BC holds the cel table.
   ld e,(hl)
   inc hl
   ld d,(hl)
   pop hl                ; Retrieve pointer to meta sprite data.
   ld (hl),e
   inc hl
   ld (hl),d
   ret
DetectCollision:
   ld a,(VDPStatus)      ; Check for sprite collision.
   bit SPRITE_COLLISION_BIT,a
   ret z
   ld a,FLAG_UP
   ld (CollisionFlag),a
   ret                 ; Return from main loop.
UpdateSATBuffers:
   ld ix,PlayerY
   call UpdateCar
   ld ix,Ash
   call UpdateCar
   ld ix,May
   call UpdateCar
   ld ix,Iris
   call UpdateCar
   ret
UpdateCar:
   ld b,4                ; 4 loops, each  loop calculating 2 y-positions.
   ld a,(ix+0)           ; Get the car's y-position.
   ld c,a                ; Save it in register C.
   ld h,(ix+3)           ; Get the meta sprite data pointer,
   ld l,(ix+2)           ; and store it in HL.
-:
   ld a,(hl)             ; Read offset.
   inc hl                ; Point HL to the next offset.
   add a,c               ; Apply saved y-position to offset.
   ld d,a                ; Save offset y-position in D.
   ld a,(hl)             ; Get new offset.
   inc hl                ; Point HL to next offset.
   add a,c               ; Apply saved y-position to offset.
   ld e,a                ; Save this offet y-position in E
   push de               ; Push the two offset y-positions to the stack.
   djnz -                ; Perform all 4 loops, then continue...
   ld de,16              ; Fast forward the meta sprite data pointer, so we
   add hl,de             ; can read the buffer index.
   ld a,(hl)             ; Read buffer index (0-2) into A.
   rla                   ; Use buffer index to calculate where to put the
   rla                   ; first of the offset y-position bytes.
   rla                   ; Start address = 8 x buffer index + SpriteBufferY.
   ld h,0
   ld l,a
   ld de,SpriteBufferY
   add hl,de
   ex de,hl              ; Now DE points to the desired place in the buffer.
   ld hl,0               ; Load the stack pointer into HL (because the
   add hl,sp             ; y-positions are on the stack).
   ld bc,$0008           ; Let's move these 8 bytes from the stack to the
   ldir                  ; buffer.
   ld sp,hl              ; Restore the stack pointer. Beware of NMI!!
   ld b,8                ; This time we loop 8 times.
   ld a,(ix+1)           ; Get the car's x-position.
   ld c,a                ; Save it like above.
   ld h,(ix+3)           ; Get the meta sprite data pointer.
   ld l,(ix+2)
   ld d,0                ; Add 8 to the meta sprite data pointer, so that
   ld e,8                ; we can skip past the y-offsets used in the
   add hl,de             ; calculations above.
-:
   ld a,(hl)             ; Read first x-offset.
   inc hl                ; Forward data pointer.
   add a,c               ; Apply car's x-position to the offset.
   ld e,a                ; Save offset x-position in E.
   ld a,(hl)             ; Read the character code (tile).
   inc hl                ; Forward data pointer once more.
   ld d,a                ; Save character code in D.
   push de               ; Save x and char on the stack.
   djnz -                ; Process all 8 XC pairs.
   ld a,(hl)             ; Get buffer index (0-2).
   rla                   ; Calculate address of first x position, using the
   rla                   ; formula: Buffer index * 2 * 8.
   rla
   rla
   ld h,0
   ld l,a
   ld de,SpriteBufferXC
   add hl,de
   ex de,hl              ; Now DE points to the correct place in the buffer.
   ld hl,0               ; Load HL with the stack pointer.
   add hl,sp
   ld bc,$0010           ; Block move 16 bytes.
   ldir                  ; Do it!
   ld sp,hl              ; Restore the stack pointer.
   ret                   ; Return from function UpdateCar.
.ends
; ---------------------
.section "The player" free
InitializePlayer:
   ld hl,FIRST_PLAYER_TILE
   PrepareVram
   ld hl,PlayerCar_Tiles
   ld bc,PLAYER_METASPRITE_SIZE
   call LoadVRAM
   ld a,PLAYER_Y_START
   ld (PlayerY),a
   ld a,PLAYER_X_START
   ld (PlayerX),a
   ld hl,PlayerCel0
   ld (PlayerMetaSpriteDataPointer),hl
   ld ix,PlayerY
   call UpdateCar
   ret
MovePlayer:
   ld a,(Joystick1)
   bit PLAYER1_JOYSTICK_RIGHT,a
   jp nz,+
   ld hl,RandomSeed+1    ; Modify MSB of seed whenever player moves right.
   dec (hl)
   ld a,(PlayerX)
   cp RIGHT_BORDER
   jp nc,+
   add a,PLAYER_HORIZONTAL_SPEED
   ld (PlayerX),a
   ret
+:
   bit PLAYER1_JOYSTICK_LEFT,a
   ret nz
   ld hl,RandomSeed+1    ; Modify MSB of seed whenever player moves left.
   inc (hl)
   ld a,(PlayerX)
   cp LEFT_BORDER
   ret c
   sub PLAYER_HORIZONTAL_SPEED
   ld (PlayerX),a
   ret
.ends
; ---------------------
.section "Enemy code" free
InitializeEnemies:
   ld hl,FIRST_ENEMY_TILE
   PrepareVram
   ld hl,EnemyCar_Tiles
   ld bc,ENEMY_METASPRITE_SIZE
   call LoadVRAM
   ld a,ASH_Y_START
   ld (Ash.y),a
   ld a,ASH_X_START
   ld (Ash.x),a
   ld hl,AshCel0
   ld (Ash.metasprite),hl
   ld a,1
   ld (Ash.index),a
   ld a,MAY_Y_START
   ld (May.y),a
   ld a,MAY_X_START
   ld (May.x),a
   ld hl,MayCel0
   ld (May.metasprite),hl
   ld a,2
   ld (May.index),a
   ld a,IRIS_Y_START
   ld (Iris.y),a
   ld a,IRIS_X_START
   ld (Iris.x),a
   ld hl,IrisCel0
   ld (Iris.metasprite),hl
   ld a,3
   ld (Iris.index),a
   ld ix,Ash
   call UpdateCar
   ld ix,May
   call UpdateCar
   ld ix,Iris
   call UpdateCar
   ret
MoveEnemy:
   call MoveEnemyVertically
   call MoveEnemyHorizontally
   ret
MoveEnemyVertically:
   ld a,(ix+0)           ; Get enemy y-position.
   add a,ENEMY_VERTICAL_SPEED
   ld (ix+0),a
   cp BOTTOM_BORDER
   ret nz
   call ResetEnemy
   ret
MoveEnemyHorizontally:
   ld a,(ix+6)           ; Get direction
   cp GOING_RIGHT
   jp nz,+
   call MoveEnemyRight
   ret
+:
   cp GOING_LEFT
   call z,MoveEnemyLeft
   ret
MoveEnemyRight:
   ld a,(ix+1)           ; Get enemy x-position.
   cp ENEMY_RIGHT_BORDER
   jp c,+
   call ToggleEnemyDirection
   ret
+:
   add a,ENEMY_HORIZONTAL_SPEED
   ld (ix+1),a
   ret
MoveEnemyLeft:
   ld a,(ix+1)           ; Get enemy x-position.
   cp ENEMY_LEFT_BORDER
   jp nc,+
   call ToggleEnemyDirection
   ret
+:
   sub ENEMY_HORIZONTAL_SPEED
   ld (ix+1),a
   ret
ToggleEnemyDirection:
   ld a,(ix+6)           ; Get enemy direction.
   cp GOING_LEFT
   jp nz,+
   ld a,GOING_RIGHT
   ld (ix+6),a
   ret
+:
   ld a,GOING_LEFT
   ld (ix+6),a
   ret
ResetEnemy:
   call GetRandomNumber
   and %00001111         ; Apply mask so that A contains a value between 0-31.
   ld d,0
   ld e,a
   ld hl,RespawnTable
   add hl,de
   ld a,(hl)
   ld (ix+1),a           ; Enemy's x-position.
   call GetRandomNumber
   and EASY_MODE_MASK    ; Will the car move r/l, or just straight down?
   ld (ix+6),a
   ret
AnimateEnemies:
   ld ix,Ash
   ld bc,AshCelTable
   ld hl,Ash.metasprite
   call AnimateCar
   ld ix,May
   ld bc,MayCelTable
   ld hl,May.metasprite
   call AnimateCar
   ld ix,Iris
   ld bc,IrisCelTable
   ld hl,Iris.metasprite
   call AnimateCar
   ret
.ends
; ---------------------
.section "Misc functions" free
Housekeeping:
   call ReadJoysticks
   call IncrementFrameCounter
   ld hl,RandomSeed      ; Modify LSB of seed every frame.
   inc (hl)
   ret
IncrementFrameCounter:
   ld hl,FrameCounter
   inc (hl)
   ret
.ends
; ---------------------
.section "VDP functions" free
LoadVDPRegisters:
   ld b,ALL_VDP_REGISTERS
   ld c,VDP_WRITE_REGISTER_COMMAND
-: ld a,(hl)             ; HL = Pointer to 11 bytes of data.
   out (VDP_CONTROL),a
   ld a,c
   out (VDP_CONTROL),a
   inc hl
   inc c
   djnz -
   ret
LoadImage:
   ld hl,ADDRESS_OF_FIRST_TILE
   PrepareVram
   ld l,(ix+0)           ; Load pointer to first tile into HL.
   ld h,(ix+1)
   ld c,(ix+2)           ; Load amount of tiles into BC.
   ld b,(ix+3)
   call LoadVRAM
   ld hl,TILEMAP_ADDRESS ; Load tilemap.
   PrepareVram
   ld l,(ix+4)           ; Load pointer to first tilemap word into HL.
   ld h,(ix+5)
   ld c,(ix+6)           ; Amount of bytes to load.
   ld b,(ix+7)
   call LoadVRAM
   ld hl,PALETTE_ADDRESS
   PrepareVram
   ld l,(ix+8)          ; Load pointer to palette data into HL.
   ld h,(ix+9)
   ld c,(ix+10)         ; Load amount of colors into BC.
   ld b,(ix+11)
   call LoadVRAM
   ret
LoadSAT:
   ld hl,SAT_Y_TABLE
   PrepareVram
   ld hl,SpriteBufferY
   ld c,VDP_DATA
   call Outi_64
   ld hl,SAT_XC_TABLE
   PrepareVram
   ld hl,SpriteBufferXC
   ld c,VDP_DATA
   call Outi_128
   ret
.ends
; ---------------------
.section "Data" free
PlayerCel0:
   .db 0 0 0 0 16 16 16 16 ; Y-offset.
   .db 0 64 8 66 16 68 24 70 0 72 8 74 16 76 24 78 ; X-offset + char pairs.
   .db 0                 ; Sprite buffer index.
PlayerCel1:
   .db 0 0 0 0 16 16 16 16
   .db 0 88 8 66 16 68 24 90 0 92 8 74 16 76 24 94
   .db 0
PlayerCel2:
   .db 0 0 0 0 16 16 16 16
   .db 0 80 8 66 16 68 24 82 0 84 8 74 16 76 24 86
   .db 0
PlayerCelTable:
   .dw PlayerCel0
   .dw PlayerCel1
   .dw PlayerCel2

; Enemies
AshCel0:
   .db 0 0 0 0 16 16 16 16
   .db 0 32 8 34 16 36 24 38 0 40 8 42 16 44 24 46
   .db 1
AshCel1:
   .db 0 0 0 0 16 16 16 16
   .db 0 56 8 34 16 36 24 58 0 60 8 42 16 44 24 62
   .db 1
AshCel2:
   .db 0 0 0 0 16 16 16 16
   .db 0 48 8 34 16 36 24 50 0 52 8 42 16 44 24 54
   .db 1
AshCelTable:
   .dw AshCel0
   .dw AshCel1
   .dw AshCel2
MayCel0:
   .db 0 0 0 0 16 16 16 16
   .db 0 32 8 34 16 36 24 38 0 40 8 42 16 44 24 46
   .db 2
MayCel1:
   .db 0 0 0 0 16 16 16 16
   .db 0 56 8 34 16 36 24 58 0 60 8 42 16 44 24 62
   .db 2
MayCel2:
   .db 0 0 0 0 16 16 16 16
   .db 0 48 8 34 16 36 24 50 0 52 8 42 16 44 24 54
   .db 2
MayCelTable:
   .dw MayCel0
   .dw MayCel1
   .dw MayCel2
IrisCel0:
   .db 0 0 0 0 16 16 16 16
   .db 0 32 8 34 16 36 24 38 0 40 8 42 16 44 24 46
   .db 3
IrisCel1:
   .db 0 0 0 0 16 16 16 16
   .db 0 56 8 34 16 36 24 58 0 60 8 42 16 44 24 62
   .db 3
IrisCel2:
   .db 0 0 0 0 16 16 16 16
   .db 0 48 8 34 16 36 24 50 0 52 8 42 16 44 24 54
   .db 3
IrisCelTable:
   .dw IrisCel0
   .dw IrisCel1
   .dw IrisCel2
RespawnTable:
   .db 20 40 60 80 100 120 140 150
   .db 25 43 63 83 92 102 119 145
   .db 28 44 64 108 126 140 98 123 142
   .db 30 46 66 86 140 84 95 105

RacetrackTiles:
   .include "Race\Racetrack_tiles.inc"
RacetrackTilesEnd:
RacetrackTilemap:
   .include "Race\Racetrack_tilemap.inc"
RacetrackPalette:
   .include "Race\Racetrack_palette.inc"
RacetrackPaletteEnd:
PlayerCar_Tiles:
   .include "Race\PlayerCar_tiles.inc"
EnemyCar_Tiles:
   .include "Race\EnemyCar_tiles.inc"
Sprites_Palette:
   .include "Race\Sprites_palette.inc"
RacetrackMockupData:
   .dw RacetrackTiles    ; Pointer to tile data.
   .dw RacetrackTilesEnd-RacetrackTiles ; Tile data (bytes) to write.
   .dw RacetrackTilemap ; Pointer to tilemap data.
   .dw WHOLE_NAMETABLE  ; Overwrite the whole nametable.
   .dw RacetrackPalette ; Pointer to palette.
   .dw RacetrackPaletteEnd-RacetrackPalette ; Amount of colors.

TitlescreenTiles:
   .include "Title\Titlescreen_tiles.inc"
TitlescreenTilesEnd:
TitlescreenTilemap:
   .include "Title\Titlescreen_tilemap.inc"
TitlescreenPalette:
   .include "Title\Titlescreen_palette.inc"
TitlescreenPaletteEnd:
TitlescreenImageData:
   .dw TitlescreenTiles  ; Pointer to tile data.
   .dw TitlescreenTilesEnd-TitlescreenTiles ; Tile data (bytes) to write.
   .dw TitlescreenTilemap ; Pointer to tilemap data.
   .dw VISIBLE_PART_OF_SCREEN ; Amount of bytes to write to tilemap.
   .dw TitlescreenPalette ; Pointer to palette.
   .dw TitlescreenPaletteEnd-TitlescreenPalette ; Amount of colors.

RegisterInitValues:
   .db %10000110         ; reg. 0, display and interrupt mode.
                         ; bit 3 = shift sprites to the left (disabled).
                         ; 4 = line interrupt (disabled - see register 10).
                         ; 5 = blank left column (disabled).
                         ; 6 = hori. scroll inhibit (disabled).
                         ; 7 = vert. scroll inhibit (enabled).
   .db %11100000         ; reg. 1, display and interrupt mode.
                         ; bit 0 = zoomed sprites (disabled).
                         ; 1 = 8 x 16 sprites (disabled).
                         ; 5 = frame interrupt (enabled).
                         ; 6 = display (enabled).
   .db $ff               ; reg. 2, name table address.
                         ; $ff = name table at $3800.
   .db $ff               ; reg. 3, n.a. (always set it to $ff).
   .db $ff               ; reg. 4, n.a. (always set it to $ff).
   .db $ff               ; reg. 5, sprite attribute table.
                         ; $ff = sprite attrib. table at $3F00.
   .db $ff               ; reg. 6, sprite tile address.
                         ; $ff = sprite tiles in bank 2.
   .db %11110000         ; reg. 7, border color.
                         ; set to color 0 in bank 2.
   .db $00               ; reg. 8, horizontal scroll value = 0.
   .db $00               ; reg. 9, vertical scroll value = 0.
   .db $ff               ; reg. 10, raster line interrupt. (disabled).
ReleaseNotes:
   .db ".... " 0
.ends
; ---------------------
.section "Outiblock" free
Outi_128:
   .rept 64
   outi
   .endr
Outi_64:
   .rept 64
   outi
   .endr
   ret
.ends