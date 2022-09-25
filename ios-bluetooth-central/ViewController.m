//
//  ViewController.m
//  ios-bluetooth-central
//
//  Created by Simon Taylor on 23/09/2022.
//

#import "ViewController.h"
#import <mach/mach_time.h>

@interface ViewController ()

@end

@implementation ViewController
{
    CBCentralManager* centralManager_;
    CBUUID* serviceUuid_;
    CBUUID* characteristicUuid_;
    
    CBPeripheral* peripheral_;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self startClient];
}

- (void)startClient {
    centralManager_ = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
    serviceUuid_ = [CBUUID UUIDWithString:@"13640001-4EC4-4D67-AEAC-380C85DF4043"];
    characteristicUuid_ = [CBUUID UUIDWithString:@"13640002-4EC4-4D67-AEAC-380C85DF4043"];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if(central.state >= CBManagerStatePoweredOn) {
        NSLog(@"Starting scan");
        [centralManager_ scanForPeripheralsWithServices:@[serviceUuid_] options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"Discovered %@", peripheral.name);
    if([@"iOS Demo" isEqualToString:advertisementData[CBAdvertisementDataLocalNameKey]]) {
        peripheral_ = peripheral;
        [centralManager_ stopScan];
        [centralManager_ connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected");
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(nullable NSError *)error {
    NSLog(@"Discovered services");
    for (CBService *service in peripheral.services) {
       NSLog(@"Discovered service %@", service);
        if([service.UUID.data isEqualToData:serviceUuid_.data]) {
            NSLog(@"Found service");
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(nullable NSError *)error {
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Discovered characteristic %@", characteristic);
        if([characteristic.UUID.data isEqualToData:characteristicUuid_.data]) {
            NSLog(@"Found the one we want");
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
    uint64_t callbackTime = getMachTimestampUs();
    static uint64_t lastCallbackTime = 0;
    
    if([characteristic.UUID.data isEqualToData:characteristicUuid_.data]) {
        // Update the controller state from the BLE data
        const uint16_t* cbData = (const uint16_t*)characteristic.value.bytes;
        NSLog(@"Received updated count: %hu, gap %llu", cbData[0], callbackTime - lastCallbackTime);
        if(callbackTime - lastCallbackTime > 100000) {
            NSLog(@"BIG GAP!");
        }
        lastCallbackTime = callbackTime;
    }
}


uint64_t getMachTimestampUs() {
    // Get conversion factors from ticks to nanoseconds
    struct mach_timebase_info timebase;
    mach_timebase_info(&timebase);
    
    // convert to us
    uint64_t ticks = mach_absolute_time();
    uint64_t machTimeUs = (ticks * timebase.numer) / (timebase.denom * 1000);
    return machTimeUs;
}

@end
