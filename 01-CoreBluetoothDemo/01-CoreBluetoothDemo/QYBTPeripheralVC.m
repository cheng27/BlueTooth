//
//  QYBTPeripheralVC.m
//  01-CoreBluetoothDemo
//
//  Created by qingyun on 15/12/22.
//  Copyright © 2015年 qingyun. All rights reserved.
//

#import "QYBTPeripheralVC.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "QYTransfer.h"

@interface QYBTPeripheralVC () <UITextViewDelegate,CBPeripheralManagerDelegate>
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (nonatomic,strong) CBPeripheralManager *peripheralManager;
@property (nonatomic,strong) CBMutableCharacteristic *characteristics2Send;
@property (nonatomic,strong) NSData *data2Send;
@property (nonatomic,assign) NSInteger data2SendIndex;
@property (weak, nonatomic) IBOutlet UISwitch *advertisingSwitch;
@end

@implementation QYBTPeripheralVC

#pragma mark - view life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - setters & getters

- (CBPeripheralManager *)peripheralManager
{
    if (_peripheralManager == nil) {
        _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
    }
    return _peripheralManager;
}

#pragma mark - CBPeripheralManagerDelegate

//当PeripheralManager设备的状态更新时，会回调该方法（peripheralManager对象创建时也会调用该方法）
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    //必须上电
    if (peripheral.state != CBPeripheralManagerStatePoweredOn) {
        NSLog(@"[INFO]:蓝牙未开启!");
        return;
    }
    //创建服务
    CBMutableService *service = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:TRANSFER_SERVER_UUID] primary:YES];
    
    //创建特性
    self.characteristics2Send = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID] properties:CBCharacteristicPropertyNotify value:nil permissions:CBAttributePermissionsReadEncryptionRequired] ;
    
    service.characteristics = @[self.characteristics2Send];
    
    //添加服务
    [self.peripheralManager addService:service];
}

//已经开始Advertising
- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:%@",error);
        return;
    }
    NSLog(@"[INFO]:开始Advertising...");
}

//当Peripheral设备收到订阅时的回调
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"[INFO]:接到订阅");
    //构造数据
    self.data2Send = [_textView.text dataUsingEncoding:NSUTF8StringEncoding];
    
    self.data2SendIndex = 0;
    
    [self sendData];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"[INFO]:解除订阅");
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral
{
    NSLog(@"[INFO]:再次准备好发送!");
    [self sendData];
}

#pragma mark - text view delegate
- (void)textViewDidBeginEditing:(UITextView *)textView {
    UIBarButtonItem *rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
    self.navigationItem.rightBarButtonItem = rightBarButtonItem;
}

- (void)textViewDidChange:(UITextView *)textView
{
    if (self.peripheralManager.isAdvertising) {
        [self.peripheralManager stopAdvertising];
        self.advertisingSwitch.on = NO;
    }
    
}

#pragma mark - misc process
- (void)sendData
{
    // 判断是否需要发送EOM
    if (self.data2SendIndex >= self.data2Send.length) {
        NSData *data = [EOM dataUsingEncoding:NSUTF8StringEncoding];
        BOOL isOK = [self.peripheralManager updateValue:data forCharacteristic:self.characteristics2Send onSubscribedCentrals:nil];
        if (isOK) {
            NSLog(@"[INFO]:EOM已发送!");
        }
        return;
    }
    
    BOOL canSend = YES;
    do {
        // 1.剩余需要发送的量
        NSInteger amount2Send = self.data2Send.length - self.data2SendIndex;
        
        // 2.本次要发送的数据的长度
        NSInteger length = amount2Send > BTLE_MTU ? BTLE_MTU : amount2Send;
        
        // 3.本次要发送的数据
        NSData *data = [NSData dataWithBytes:self.data2Send.bytes + self.data2SendIndex length:length];
        
        // 4.发送
         canSend = [self.peripheralManager updateValue:data forCharacteristic:self.characteristics2Send onSubscribedCentrals:nil];
        
        if (!canSend) {
            //硬件已不能再发送，等下次硬件再次准备好的时候发送
            //
            return;
        }
        
        //打印一下已经发送的数据
        NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[DEBUG]:已经发送 - %@ ",dataStr);
        
        //更新记录发送位置的索引
        self.data2SendIndex += length;
        
    } while (canSend);
}
#pragma mark - events handling
- (void)dismissKeyboard {
    self.navigationItem.rightBarButtonItem = nil;
    [_textView resignFirstResponder];
}

- (IBAction)advertising:(UISwitch *)sender {
    if (sender.on) {
        [self.peripheralManager startAdvertising:@{CBAdvertisementDataServiceUUIDsKey:@[[CBUUID UUIDWithString:TRANSFER_SERVER_UUID]]}];
    }else
    {
        [self.peripheralManager stopAdvertising];
    }
}


@end
